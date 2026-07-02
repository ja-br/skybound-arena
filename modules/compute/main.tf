# Compute module: the deploy target the CI/CD pipeline ships into.
#
#   players ─443/80─> ALB ─> [blue|green] target group ─> Fargate task (app_port)
#
# The ECS service uses the CODE_DEPLOY deployment controller: Terraform stands up
# the service with a bootstrap task revision and the blue target group, then
# CodeDeploy owns every subsequent blue/green traffic shift. 

data "aws_caller_identity" "current" {}

locals {
  name      = "${var.env}-skybound"
  use_https = var.certificate_arn != ""
  # First image the service boots on. Push an app image tagged `bootstrap` to ECR
  # before applying the service (see the module README). The pipeline replaces it.
  bootstrap_image = "${aws_ecr_repository.app.repository_url}:bootstrap"
}

# --- Image registry ----------------------------------------------------------
resource "aws_ecr_repository" "app" {
  name                 = "${var.env}-skybound-arena"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${local.name}-arena" }
}

# --- Logs --------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${local.name}-api"
  retention_in_days = var.log_retention_days
}

# --- IAM: execution role -----------------------------------------------------
data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.name}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- IAM: task role ----------------------------------------------------------
resource "aws_iam_role" "task" {
  name               = "${local.name}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

data "aws_iam_policy_document" "task" {
  statement {
    sid = "DynamoDataAccess"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:Query",
    ]
    resources = [
      var.players_table_arn,
      "${var.players_table_arn}/index/*", # leaderboard GSI
      var.matches_table_arn,
    ]
  }
}

resource "aws_iam_role_policy" "task" {
  name   = "${local.name}-task-dynamo"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task.json
}

# --- Load balancer + blue/green target groups --------------------------------
resource "aws_lb" "this" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids
}

# Two target groups CodeDeploy swaps between. target_type = ip for awsvpc/Fargate.
resource "aws_lb_target_group" "blue" {
  name        = "${local.name}-blue"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "green" {
  name        = "${local.name}-green"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

# Production listener CodeDeploy shifts. HTTP:80 in dev; HTTPS:443 when a cert is set.
resource "aws_lb_listener" "prod" {
  load_balancer_arn = aws_lb.this.arn
  port              = local.use_https ? 443 : 80
  protocol          = local.use_https ? "HTTPS" : "HTTP"
  ssl_policy        = local.use_https ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null
  certificate_arn   = local.use_https ? var.certificate_arn : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  # CodeDeploy rewrites default_action.target_group_arn on every shift.
  lifecycle {
    ignore_changes = [default_action]
  }
}

# --- ECS cluster + bootstrap task definition + service -----------------------
resource "aws_ecs_cluster" "this" {
  name = "${local.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Bootstrap revision only, the pipeline's rendered taskdef.json supersedes it.
resource "aws_ecs_task_definition" "app" {
  family                   = var.container_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = local.bootstrap_image
      essential = true
      portMappings = [
        { containerPort = var.app_port, protocol = "tcp" }
      ]
      environment = [
        { name = "AWS_REGION", value = var.region },
        { name = "PLAYERS_TABLE", value = var.players_table_name },
        { name = "MATCHES_TABLE", value = var.matches_table_name },
        { name = "VERSION", value = "bootstrap" },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = var.container_name
        }
      }
    }
  ])

  # The pipeline manages task revisions ignore drift after bootstrap.
  lifecycle {
    ignore_changes = [container_definitions]
  }
}

resource "aws_ecs_service" "app" {
  name            = "${local.name}-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.app_sg_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = var.container_name
    container_port   = var.app_port
  }

  # Don't block apply on health while bootstrapping before the first real deploy.
  wait_for_steady_state = false

  # CodeDeploy owns these after bootstrap Terraform must not revert its shifts.
  lifecycle {
    ignore_changes = [task_definition, load_balancer, desired_count]
  }

  depends_on = [aws_lb_listener.prod]
}
