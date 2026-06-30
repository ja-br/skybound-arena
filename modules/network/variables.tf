variable "env" {
  description = "Environment name (dev/staging/prod) prefixes resource names"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across (>= 2 for HA)"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "One CIDR per public subnet, length should match azs"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "One CIDR per private subnet, length should match azs"
  type        = list(string)
}

variable "nat_gateway_count" {
  description = "NAT gateways to create, 1 in dev, >= AZ count in prod"
  type        = number
  default     = 1

  validation {
    condition     = var.nat_gateway_count >= 1
    error_message = "Need at least one NAT gateway for private subnets to reach the internet"
  }
}
