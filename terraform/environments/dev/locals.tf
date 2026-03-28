# ==============================================================================
# Local Values
# Computed values derived from variables
# Centralizes naming conventions and common values
# ==============================================================================
locals {
  # Common name prefix for all resources
  name_prefix = "${var.project}-${var.environment}"

  # Common tags merged with resource-specific tags
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = "platform-team"
    Repository  = "supabase-infrastructure"
  }

  # Networking
  vpc_name = "${local.name_prefix}-vpc"

  # EKS
  eks_cluster_name = var.eks_cluster_name

  # RDS
  db_cluster_identifier = "${local.name_prefix}-aurora"

  # S3
  storage_bucket_name = "${var.storage_bucket_name}-${var.environment}-904667241500"

  # Secrets Manager secret names
  secret_names = {
    db         = "${local.name_prefix}/db"
    jwt        = "${local.name_prefix}/jwt"
    dashboard  = "${local.name_prefix}/dashboard"
    analytics  = "${local.name_prefix}/analytics"
    realtime   = "${local.name_prefix}/realtime"
    meta       = "${local.name_prefix}/meta"
  }
}
