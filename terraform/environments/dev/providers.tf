# ==============================================================================
# Provider Configuration
# Uses exec-based authentication for EKS to handle token refresh automatically
# Static tokens expire after 15 minutes which breaks long-running applies
# ==============================================================================

# AWS Provider
provider "aws" {
  region = var.aws_region

  # Default tags applied to all resources for cost tracking and governance
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "platform-team"
      Repository  = "supabase-infrastructure"
    }
  }
}

# Kubernetes provider
# Uses exec-based auth to fetch fresh tokens from EKS
# This prevents token expiry during long terraform applies
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      var.aws_region
    ]
  }
}

# Helm provider
# Uses same exec-based auth as kubernetes provider
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        module.eks.cluster_name,
        "--region",
        var.aws_region
      ]
    }
  }
}

# Kubectl provider for applying raw Kubernetes manifests
# Used for network policies and ESO resources
provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      module.eks.cluster_name,
      "--region",
      var.aws_region
    ]
  }
}

# PostgreSQL provider for Aurora DB bootstrap
# Uses AWS RDS IAM auth - no password needed
# Requires network connectivity to Aurora private endpoint
# Run terraform from within VPC (bastion host or AWS Cloud9)
provider "postgresql" {
  scheme    = "awspostgres"
  host      = module.rds.cluster_endpoint
  port      = 5432
  database  = "postgres"
  username  = var.db_master_username
  sslmode   = "require"
  superuser = false

  # Use AWS RDS IAM authentication
  # No password needed - uses AWS credentials from environment
  aws_rds_iam_auth   = true
  aws_rds_iam_region = var.aws_region

  expected_version = "15.4"
}
