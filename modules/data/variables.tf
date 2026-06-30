variable "env" {
  description = "Environment name (dev/staging/prod). Prefixes table names."
  type        = string
}

variable "pitr_enabled" {
  description = "DynamoDB point-in-time recovery. Off in dev, on in prod."
  type        = bool
  default     = false
}
