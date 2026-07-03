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

module "observability" {
  source = "../../modules/observability"
  env    = var.env
  region = var.region

  cluster_name   = module.compute.cluster_name
  service_name   = module.compute.service_name
  alb_arn_suffix = module.compute.alb_arn_suffix

  # From compute so the dashboard's metric references match what the app emits.
  metrics_namespace = module.compute.metrics_namespace
  metrics_service   = module.compute.metrics_service
}

module "pipeline" {
  source = "../../modules/pipeline"
  env    = var.env
  region = var.region

  github_repository = var.github_repository
  github_branch     = var.github_branch

  ecr_repository_url      = module.compute.ecr_repository_url
  ecr_repository_arn      = module.compute.ecr_repository_arn
  ecs_cluster_name        = module.compute.cluster_name
  ecs_service_name        = module.compute.service_name
  task_execution_role_arn = module.compute.task_execution_role_arn
  task_role_arn           = module.compute.task_role_arn
}
