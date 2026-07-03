variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "env" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
}

variable "azs" {
  description = "Availability zones."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (one per AZ)."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (one per AZ)."
  type        = list(string)
}

variable "nat_gateway_count" {
  description = "NAT gateways. 1 in dev, 2 in prod."
  type        = number
  default     = 1
}

variable "pitr_enabled" {
  description = "DynamoDB PITR. Off in dev to save cost."
  type        = bool
  default     = false
}

variable "app_desired_count" {
  description = "ECS task count for the app service."
  type        = number
  default     = 1
}

# --- CI/CD pipeline ----------------------------------------------------------
variable "github_repository" {
  description = "GitHub repo the pipelines build from, as owner/name."
  type        = string
  default     = "ja-br/skybound-arena"
}

variable "github_branch" {
  description = "Branch the pipelines track."
  type        = string
  default     = "main"
}
