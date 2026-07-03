# Compute module: the runtime the app runs on and the deploy target.
#
#   players ─443/80─> ALB ─(prod listener rule)─> [blue|green] target group ─> Fargate task (app_port)
#
# The ECS service uses the built-in ECS blue/green strategy: updating the task
# definition (new image) makes ECS stand up a green task set, validate it, shift
# the production listener rule from blue to green, bake, then drain blue — with
# automatic rollback via the deployment circuit breaker. No CodeDeploy.

data "aws_caller_identity" "current" {}

locals {
  name      = "${var.env}-skybound"
  use_https = var.certificate_arn != ""
  # Image the service runs. Defaults to the `bootstrap` tag pushed by hand on
  # first bring-up (see README); set var.image_tag to a new tag to deploy.
  container_image = "${aws_ecr_repository.app.repository_url}:${var.image_tag}"
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

# --- IAM: ECS infrastructure role (lets ECS move the listener rule on a shift) -
data "aws_iam_policy_document" "ecs_infra_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_infra" {
  name               = "${local.name}-ecs-infra"
  assume_role_policy = data.aws_iam_policy_document.ecs_infra_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_infra" {
  role       = aws_iam_role.ecs_infra.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"
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

# Production listener. HTTP:80 in dev; HTTPS:443 when a cert is set. The default
# action is a 404 fallback — all real traffic is governed by the rule below,
# which is the one ECS shifts between blue and green.
resource "aws_lb_listener" "prod" {
  load_balancer_arn = aws_lb.this.arn
  port              = local.use_https ? 443 : 80
  protocol          = local.use_https ? "HTTPS" : "HTTP"
  ssl_policy        = local.use_https ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null
  certificate_arn   = local.use_https ? var.certificate_arn : null

  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "no route"
      status_code  = "404"
    }
  }
}

# The production listener rule ECS repoints on every blue/green shift. It starts
# on blue; ECS rewrites its target group, so ignore drift on the action.
resource "aws_lb_listener_rule" "prod" {
  listener_arn = aws_lb_listener.prod.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  lifecycle {
    ignore_changes = [action]
  }
}

# --- ECS cluster + task definition + service ---------------------------------
resource "aws_ecs_cluster" "this" {
  name = "${local.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Terraform owns this. Bumping var.image_tag registers a new revision, which is
# what triggers a blue/green deployment. VERSION is echoed by /version to prove
# which build is live after a shift (or rollback).
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
      image     = local.container_image
      essential = true
      portMappings = [
        { containerPort = var.app_port, protocol = "tcp" }
      ]
      environment = [
        { name = "AWS_REGION", value = var.region },
        { name = "PLAYERS_TABLE", value = var.players_table_name },
        { name = "MATCHES_TABLE", value = var.matches_table_name },
        { name = "VERSION", value = var.image_tag },
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
}

resource "aws_ecs_service" "app" {
  name            = "${local.name}-api"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Built-in blue/green: green stands up, validates, traffic shifts, bakes.
  deployment_configuration {
    strategy             = "BLUE_GREEN"
    bake_time_in_minutes = var.bake_time_minutes
  }

  # Auto-rollback if the deployment can't stabilise (e.g. a broken build fails
  # health checks) — the "push a bad build, watch it roll back" demo.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.app_sg_id]
    assign_public_ip = false
  }

  # target_group_arn is the current production (blue) target group; ECS shifts
  # traffic to the alternate (green) group via the production listener rule.
  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = var.container_name
    container_port   = var.app_port

    advanced_configuration {
      alternate_target_group_arn = aws_lb_target_group.green.arn
      production_listener_rule   = aws_lb_listener_rule.prod.arn
      role_arn                   = aws_iam_role.ecs_infra.arn
    }
  }

  # Don't block apply on health while bootstrapping before the first real deploy.
  wait_for_steady_state = false

  depends_on = [
    aws_lb_listener_rule.prod,
    aws_iam_role_policy_attachment.ecs_infra,
  ]
}
