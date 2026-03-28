# ==============================================================================
# Supabase Module Variables
# ==============================================================================

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for Supabase deployment"
  type        = string
  default     = "supabase"
}

variable "db_host" {
  description = "Aurora PostgreSQL cluster endpoint"
  type        = string
}

variable "db_port" {
  description = "Aurora PostgreSQL port"
  type        = number
  default     = 5432
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "storage_bucket_name" {
  description = "S3 bucket name for Supabase storage"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "storage_role_arn" {
  description = "IRSA role ARN for Supabase storage pod"
  type        = string
}

variable "eso_role_arn" {
  description = "IRSA role ARN for External Secrets Operator"
  type        = string
}

variable "secret_store_name" {
  description = "Name of the ESO SecretStore"
  type        = string
  default     = "supabase-secret-store"
}

variable "secret_names" {
  description = "Map of secret names in AWS Secrets Manager"
  type        = map(string)
}

variable "supabase_domain" {
  description = "Domain for Supabase API via Kong"
  type        = string
}

variable "studio_domain" {
  description = "Domain for Supabase Studio"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
