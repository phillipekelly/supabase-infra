# ==============================================================================
# Secrets Manager Module Variables
# ==============================================================================

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "db_master_password" {
  description = "Master password for Aurora PostgreSQL"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT secret for Supabase - minimum 32 characters"
  type        = string
  sensitive   = true
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
}

variable "analytics_public_token" {
  description = "Logflare public access token"
  type        = string
  sensitive   = true
}

variable "analytics_private_token" {
  description = "Logflare private access token"
  type        = string
  sensitive   = true
}

variable "realtime_secret_key_base" {
  description = "Secret key base for Supabase Realtime"
  type        = string
  sensitive   = true
}

variable "meta_crypto_key" {
  description = "Crypto key for Supabase Meta"
  type        = string
  sensitive   = true
}

variable "db_master_username" {
  description = "Master username for Aurora PostgreSQL"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
