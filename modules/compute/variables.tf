variable "env" {
  description = "Environment name (dev/staging/prod). Prefixes resource names."
  type        = string
}

variable "region" {
  description = "AWS region (baked into the container env + log config)."
  type        = string
}

# --- Networking (from the network + security modules) ------------------------
variable "vpc_id" {
  description = "VPC the ALB and tasks live in."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnets for the internet-facing ALB."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnets for the Fargate tasks (no public IP)."
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group for the ALB (443/80 from players)."
  type        = string
}

variable "app_sg_id" {
  description = "Security group for the tasks (app_port from the ALB only)."
  type        = string
}

# --- Data tier (from the data module) — scopes the task IAM role -------------
variable "players_table_arn" {
  description = "Players table ARN (task role gets scoped access + its GSI)."
  type        = string
}

variable "matches_table_arn" {
  description = "Matches table ARN (task role gets scoped access)."
  type        = string
}

variable "players_table_name" {
  description = "Players table name (passed to the container as PLAYERS_TABLE)."
  type        = string
}

variable "matches_table_name" {
  description = "Matches table name (passed to the container as MATCHES_TABLE)."
  type        = string
}

# --- App runtime knobs -------------------------------------------------------
variable "app_port" {
  description = "Container port the app listens on. Must match the app SG + appspec."
  type        = number
  default     = 8080
}

variable "container_name" {
  description = "Container name. Must match taskdef.json (skybound-api)."
  type        = string
  default     = "skybound-api"
}

variable "image_tag" {
  description = "ECR image tag the task runs. Bump it (new build) to trigger a blue/green deploy."
  type        = string
  default     = "bootstrap"
}

variable "bake_time_minutes" {
  description = "Minutes ECS keeps blue alive after the shift, for instant rollback."
  type        = number
  default     = 5
}

variable "cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate task memory (MiB)."
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Number of tasks. CodeDeploy manages this after bootstrap."
  type        = number
  default     = 1
}

variable "health_check_path" {
  description = "ALB target-group health check path. Load-bearing: CodeDeploy gates on it."
  type        = string
  default     = "/healthz"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the app log group."
  type        = number
  default     = 14
}

variable "certificate_arn" {
  description = "ACM cert ARN. Empty = HTTP:80 listener (dev); set = HTTPS:443 (prod)."
  type        = string
  default     = ""
}
