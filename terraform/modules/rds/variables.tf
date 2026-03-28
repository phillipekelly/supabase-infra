# ==============================================================================
# RDS Aurora PostgreSQL Module Variables
# ==============================================================================

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where RDS will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of private subnets for RDS subnet group"
  type        = list(string)
}

variable "eks_security_group_id" {
  description = "Security group ID of EKS nodes - allowed to connect to RDS"
  type        = string
}

variable "db_name" {
  description = "Name of the initial database"
  type        = string
}

variable "db_master_username" {
  description = "Master username for Aurora cluster"
  type        = string
}

variable "db_master_password" {
  description = "Master password for Aurora cluster"
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "Instance class for Aurora instances"
  type        = string
}

variable "db_backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
}

variable "availability_zones" {
  description = "Availability zones for Aurora cluster"
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
