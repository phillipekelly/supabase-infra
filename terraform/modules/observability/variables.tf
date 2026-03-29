# ==============================================================================
# Observability Module Variables
# ==============================================================================

variable "cluster_name" {
  description = "EKS cluster name - used for CloudWatch log group naming"
  type        = string
}

variable "environment" {
  description = "Environment name (development/staging/production)"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days - prevents indefinite accumulation at $0.50/GB/month"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch retention period."
  }
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------------------
# Future variables — uncomment when enabling full observability stack
# ------------------------------------------------------------------------------
# variable "grafana_admin_password" {
#   description = "Grafana admin password"
#   type        = string
#   sensitive   = true
# }
#
# variable "sns_alert_topic_arn" {
#   description = "SNS topic ARN for CloudWatch alarms"
#   type        = string
#   default     = ""
# }
#
# variable "eks_node_group_dependency" {
#   description = "EKS node group dependency for Helm releases"
#   type        = any
# }
