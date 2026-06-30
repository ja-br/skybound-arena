# Security module: the public/private tier separation 
#   Players ──443──> ALB ──> app tasks (ALB-only ingress) ──> private data tier
# No SSH anywhere — access is via SSM Session Manager

# --- ALB: the only thing players can reach -----------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.env}-skybound-alb"
  description = "ALB: accepts player HTTPS traffic from the internet"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from players"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP (redirect to HTTPS at the ALB)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env}-skybound-alb", Tier = "public" }
}

# --- App tasks: reachable ONLY from the ALB, never from the internet ----------
resource "aws_security_group" "app" {
  name        = "${var.env}-skybound-app"
  description = "App tasks: ingress only from the ALB SG"
  vpc_id      = var.vpc_id

  ingress {
    description     = "App port from the ALB only"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound (DynamoDB, ECR pulls, SSM, etc. via NAT)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.env}-skybound-app", Tier = "private" }
}
