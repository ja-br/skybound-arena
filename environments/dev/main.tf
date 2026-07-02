# dev environment: wires the shared modules with dev-sized values.

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

module "compute" {
  source = "../../modules/compute"
  env    = var.env
  region = var.region

  vpc_id             = module.network.vpc_id
  public_subnet_ids  = module.network.public_subnet_ids
  private_subnet_ids = module.network.private_subnet_ids
  alb_sg_id          = module.security.alb_sg_id
  app_sg_id          = module.security.app_sg_id

  players_table_arn  = module.data.players_table_arn
  matches_table_arn  = module.data.matches_table_arn
  players_table_name = module.data.players_table_name
  matches_table_name = module.data.matches_table_name

  desired_count = var.app_desired_count
  # certificate_arn left empty in dev → HTTP:80 listener (no ACM cert needed).
}
