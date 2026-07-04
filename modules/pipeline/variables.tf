variable "env" {
  description = "Environment name (dev/staging/prod). Prefixes resource names."
  type        = string
}

variable "region" {
  description = "AWS region the pipeline and its builds run in."
  type        = string
}

# --- Source (GitHub via CodeConnections) -------------------------------------
variable "github_repository" {
  description = "GitHub repo the pipelines build from, as owner/name."
  type        = string
  default     = "ja-br/skybound-arena"
}

variable "github_branch" {
  description = "Branch the pipelines track. Push here to trigger a run."
  type        = string
  default     = "main"
}

# --- Terraform (infra pipeline) ----------------------------------------------
variable "tf_working_dir" {
  description = "Path (from repo root) the infra pipeline runs terraform in."
  type        = string
  default     = "environments/dev"
}

variable "tf_version" {
  description = "Terraform version the CodeBuild infra projects install."
  type        = string
  default     = "1.10.5"
}

variable "state_bucket" {
  description = "S3 bucket holding remote state. Injected into `terraform init -backend-config` in CodeBuild, since backend.tf omits the account-specific bucket name."
  type        = string
}

# --- App pipeline (from the compute module) ----------------------------------
variable "ecr_repository_url" {
  description = "ECR repo the app build pushes SHA-tagged images to."
  type        = string
}

variable "ecr_repository_arn" {
  description = "ECR repo ARN (scopes push permissions)."
  type        = string
}

variable "ecs_cluster_name" {
  description = "ECS cluster the app service runs in."
  type        = string
}

variable "ecs_service_name" {
  description = "ECS service the deploy stage updates."
  type        = string
}

variable "task_family" {
  description = "ECS task-definition family the deploy stage bases new revisions on."
  type        = string
  default     = "skybound-api"
}

variable "container_name" {
  description = "Container in the task def whose image the deploy swaps."
  type        = string
  default     = "skybound-api"
}

variable "task_execution_role_arn" {
  description = "Task execution role ARN (deploy stage passes it on register-task-definition)."
  type        = string
}

variable "task_role_arn" {
  description = "Task role ARN (deploy stage passes it on register-task-definition)."
  type        = string
}
