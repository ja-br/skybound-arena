region = "us-east-1"
env    = "dev"

vpc_cidr             = "10.10.0.0/16"
azs                  = ["us-east-1a", "us-east-1b"]
public_subnet_cidrs  = ["10.10.1.0/24", "10.10.2.0/24"]
private_subnet_cidrs = ["10.10.11.0/24", "10.10.12.0/24"]

nat_gateway_count = 1 # single NAT in dev
pitr_enabled      = false
