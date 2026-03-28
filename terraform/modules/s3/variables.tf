# ==============================================================================
# S3 Module Variables
# ==============================================================================

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
}

variable "bucket_name" {
  description = "Name of the S3 bucket for Supabase storage"
  type        = string
}

variable "eks_node_role_arn" {
  description = "IAM role ARN of EKS nodes - granted access to S3 bucket"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
