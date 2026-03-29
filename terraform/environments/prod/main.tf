# ==============================================================================
# Main Entry Point
# Orchestrates all modules in dependency order
# ==============================================================================

# ------------------------------------------------------------------------------
# Networking — must be created first, everything depends on VPC
# ------------------------------------------------------------------------------
module "networking" {
  source = "../../modules/networking"

  name_prefix          = local.name_prefix
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  private_subnet_cidrs = var.private_subnet_cidrs
  public_subnet_cidrs  = var.public_subnet_cidrs
  tags                 = local.common_tags
}

# ------------------------------------------------------------------------------
# S3 — independent of EKS and RDS, can be created in parallel
# ------------------------------------------------------------------------------
module "s3" {
  source = "../../modules/s3"

  name_prefix       = local.name_prefix
  bucket_name       = local.storage_bucket_name
  eks_node_role_arn = module.eks.node_role_arn
  tags              = local.common_tags
}

# ------------------------------------------------------------------------------
# Secrets Manager — independent, can be created in parallel
# Secrets populated here, consumed by ESO in EKS
# ------------------------------------------------------------------------------
module "secrets" {
  source = "../../modules/secrets"

  name_prefix              = local.name_prefix
  db_master_username       = var.db_master_username
  db_master_password       = var.db_master_password
  db_name                  = var.db_name
  jwt_secret               = var.jwt_secret
  jwt_anon_key             = var.jwt_anon_key
  jwt_service_key          = var.jwt_service_key
  dashboard_username       = var.dashboard_username
  dashboard_password       = var.dashboard_password
  analytics_public_token   = var.analytics_public_token
  analytics_private_token  = var.analytics_private_token
  realtime_secret_key_base = var.realtime_secret_key_base
  meta_crypto_key          = var.meta_crypto_key
  tags                     = local.common_tags
}

# ------------------------------------------------------------------------------
# EKS — depends on networking for subnet IDs
# Also needs secrets and s3 policy ARNs for IRSA
# ------------------------------------------------------------------------------
module "eks" {
  source = "../../modules/eks"

  name_prefix          = local.name_prefix
  cluster_name         = var.eks_cluster_name
  cluster_version      = var.eks_cluster_version
  vpc_id               = module.networking.vpc_id
  private_subnet_ids   = module.networking.private_subnet_ids
  node_instance_type   = var.eks_node_instance_type
  node_min_size        = var.eks_node_min_size
  node_max_size        = var.eks_node_max_size
  node_desired_size    = var.eks_node_desired_size
  eso_policy_arn       = module.secrets.eso_policy_arn
  s3_access_policy_arn = module.s3.s3_access_policy_arn
  aws_region           = var.aws_region
  tags                 = local.common_tags
}

# ------------------------------------------------------------------------------
# RDS Aurora — depends on networking and EKS security group
# EKS security group needed for RDS security group ingress rule
# ------------------------------------------------------------------------------
module "rds" {
  source = "../../modules/rds"

  name_prefix           = local.name_prefix
  vpc_id                = module.networking.vpc_id
  private_subnet_ids    = module.networking.private_subnet_ids
  eks_security_group_id = module.eks.node_security_group_id
  availability_zones    = var.availability_zones
  db_name               = var.db_name
  db_master_username    = var.db_master_username
  db_master_password    = var.db_master_password
  db_instance_class     = var.db_instance_class
  db_backup_retention_days = var.db_backup_retention_days
  tags                  = local.common_tags
}

# ------------------------------------------------------------------------------
# Supabase — depends on everything above
# Deploys Helm chart, ESO, and network policies
# ------------------------------------------------------------------------------
module "supabase" {
  source = "../../modules/supabase"

  name_prefix         = local.name_prefix
  namespace           = var.supabase_namespace
  db_host             = module.rds.cluster_endpoint
  db_port             = 5432
  db_name             = var.db_name
  storage_bucket_name = module.s3.bucket_name
  aws_region          = var.aws_region
  storage_role_arn    = module.eks.storage_role_arn
  eso_role_arn        = module.eks.eso_role_arn
  secret_names        = module.secrets.secret_names
  supabase_domain     = var.supabase_domain
  studio_domain       = var.studio_domain
  tags                = local.common_tags
}

# ------------------------------------------------------------------------------
# Observability — CloudWatch log groups + future Prometheus/Grafana/Fluent Bit
# ------------------------------------------------------------------------------
module "observability" {
  source = "../../modules/observability"

  cluster_name       = var.eks_cluster_name
  environment        = var.environment
  aws_region         = var.aws_region
  log_retention_days = 30
  tags               = local.common_tags
}
