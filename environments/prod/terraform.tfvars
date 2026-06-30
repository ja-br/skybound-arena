region = "us-east-1"
env    = "prod"

vpc_cidr             = "10.30.0.0/16"
azs                  = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.30.1.0/24", "10.30.2.0/24"]
private_subnet_cidrs = ["10.30.11.0/24", "10.30.12.0/24"]

nat_gateway_count = 2    # one NAT per AZ — no single-AZ egress failure
pitr_enabled      = true # point-in-time recovery on for prod data
