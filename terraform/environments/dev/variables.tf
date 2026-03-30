# ==============================================================================
# Input Variables
# All variables include description, type, and validation where appropriate
# Sensitive variables marked with sensitive = true
# ==============================================================================

# ------------------------------------------------------------------------------
# General
# ------------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region where all resources will be deployed"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "AWS region must be a valid region format (e.g., us-east-1, eu-west-1)"
  }
}

variable "environment" {
  description = "Deployment environment name (used for tagging and naming)"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development", "sit"], var.environment)
    error_message = "Environment must be one of: production, staging, development"
  }
}

variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "supabase"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens"
  }
}

# ------------------------------------------------------------------------------
# Networking
# ------------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "VPC CIDR must be a valid IPv4 CIDR block"
  }
}

variable "availability_zones" {
  description = "List of availability zones to deploy resources across (minimum 2 for HA)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones required for high availability"
  }
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "At least 2 private subnet CIDRs required for high availability"
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "At least 2 public subnet CIDRs required for high availability"
  }
}

# ------------------------------------------------------------------------------
# EKS
# ------------------------------------------------------------------------------
variable "eks_cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "supabase-eks"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.eks_cluster_name))
    error_message = "EKS cluster name must start with a letter and contain only alphanumeric characters and hyphens"
  }
}

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.eks_cluster_version))
    error_message = "EKS cluster version must be a valid Kubernetes version (e.g., 1.31)"
  }
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.medium"

  validation {
    condition     = can(regex("^[a-z][0-9][a-z]?\\.[a-z0-9]+$", var.eks_node_instance_type))
    error_message = "Must be a valid EC2 instance type (e.g., t3.medium, m5.large)"
  }
}

variable "eks_node_min_size" {
  description = "Minimum number of worker nodes in the node group"
  type        = number
  default     = 2

  validation {
    condition     = var.eks_node_min_size >= 1
    error_message = "Minimum node count must be at least 1"
  }
}

variable "eks_node_max_size" {
  description = "Maximum number of worker nodes in the node group"
  type        = number
  default     = 6

  validation {
    condition     = var.eks_node_max_size >= var.eks_node_min_size
    error_message = "Maximum node count must be greater than or equal to minimum node count"
  }
}

variable "eks_node_desired_size" {
  description = "Desired number of worker nodes in the node group"
  type        = number
  default     = 2
}

# ------------------------------------------------------------------------------
# RDS Aurora PostgreSQL
# ------------------------------------------------------------------------------
variable "db_name" {
  description = "Name of the PostgreSQL database"
  type        = string
  default     = "postgres"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_name))
    error_message = "Database name must start with a letter and contain only alphanumeric characters and underscores"
  }
}

variable "db_master_username" {
  description = "Master username for the Aurora PostgreSQL cluster"
  type        = string
  default     = "supabase_admin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_master_username))
    error_message = "Database username must start with a letter and contain only alphanumeric characters and underscores"
  }
}

variable "db_instance_class" {
  description = "Aurora instance class for database nodes"
  type        = string
  default     = "db.r6g.large"
}

variable "db_backup_retention_days" {
  description = "Number of days to retain automated database backups"
  type        = number
  default     = 7

  validation {
    condition     = var.db_backup_retention_days >= 1 && var.db_backup_retention_days <= 35
    error_message = "Backup retention must be between 1 and 35 days"
  }
}

# ------------------------------------------------------------------------------
# S3
# ------------------------------------------------------------------------------
variable "storage_bucket_name" {
  description = "Name of the S3 bucket for Supabase file storage"
  type        = string
  default     = "supabase-storage"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.storage_bucket_name))
    error_message = "S3 bucket name must be lowercase, start and end with alphanumeric characters"
  }
}

# ------------------------------------------------------------------------------
# Supabase
# ------------------------------------------------------------------------------
variable "supabase_namespace" {
  description = "Kubernetes namespace for Supabase deployment"
  type        = string
  default     = "supabase"
}

variable "supabase_domain" {
  description = "Primary domain for Supabase API (Kong)"
  type        = string
  default     = "supabase.yourdomain.com"
}

variable "studio_domain" {
  description = "Domain for Supabase Studio admin UI"
  type        = string
  default     = "studio.yourdomain.com"
}

# ------------------------------------------------------------------------------
# Secrets — sensitive values, never hardcoded
# Provided via terraform.tfvars (gitignored) or environment variables
# ------------------------------------------------------------------------------
variable "db_master_password" {
  description = "Master password for Aurora PostgreSQL cluster"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_master_password) >= 16
    error_message = "Database password must be at least 16 characters"
  }
}

variable "jwt_secret" {
  description = "JWT secret for Supabase - minimum 32 characters"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.jwt_secret) >= 32
    error_message = "JWT secret must be at least 32 characters"
  }
}

variable "jwt_anon_key" {
  description = "JWT anon key for Supabase"
  type        = string
  sensitive   = true
}

variable "jwt_service_key" {
  description = "JWT service role key for Supabase"
  type        = string
  sensitive   = true
}

variable "dashboard_username" {
  description = "Supabase Studio dashboard username"
  type        = string
  sensitive   = true
}

variable "dashboard_password" {
  description = "Supabase Studio dashboard password"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.dashboard_password) >= 12
    error_message = "Dashboard password must be at least 12 characters"
  }
}

variable "analytics_public_token" {
  description = "Logflare public access token - minimum 32 characters"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.analytics_public_token) >= 32
    error_message = "Analytics public token must be at least 32 characters"
  }
}

variable "analytics_private_token" {
  description = "Logflare private access token - minimum 32 characters"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.analytics_private_token) >= 32
    error_message = "Analytics private token must be at least 32 characters"
  }
}

variable "realtime_secret_key_base" {
  description = "Secret key base for Supabase Realtime - minimum 64 characters"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.realtime_secret_key_base) >= 64
    error_message = "Realtime secret key base must be at least 64 characters"
  }
}

variable "meta_crypto_key" {
  description = "Crypto key for Supabase Meta - minimum 32 characters"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.meta_crypto_key) >= 32
    error_message = "Meta crypto key must be at least 32 characters"
  }
}
