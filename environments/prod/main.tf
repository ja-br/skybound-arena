# prod environment wires the shared modules with prod-sized values
# Identical structure to dev and staging only terraform.tfvars differs

module "network" {
  source               = "../../modules/network"
  env                  = var.env
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  nat_gateway_count    = var.nat_gateway_count
}

module "security" {
  source = "../../modules/security"
  env    = var.env
  vpc_id = module.network.vpc_id
}

module "data" {
  source       = "../../modules/data"
  env          = var.env
  pitr_enabled = var.pitr_enabled
}
