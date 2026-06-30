# dev environment wires the shared modules with dev-sized values.
# prod is the SAME file with bigger CIDRs, nat_gateway_count = 2, pitr on.
# That sameness is the point: it proves one-command repeatability.

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
