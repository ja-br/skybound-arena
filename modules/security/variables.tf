variable "env" {
  description = "Environment name (dev/staging/prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC the security groups belong to (from the network module)"
  type        = string
}

variable "app_port" {
  description = "Container port the app listens on"
  type        = number
  default     = 8080
}
