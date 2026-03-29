# ==============================================================================
# Observability Module Outputs
# ==============================================================================

output "eks_log_group_name" {
  description = "CloudWatch log group name for EKS control plane logs"
  value       = aws_cloudwatch_log_group.eks_control_plane.name
}

output "eks_log_group_arn" {
  description = "CloudWatch log group ARN for EKS control plane logs"
  value       = aws_cloudwatch_log_group.eks_control_plane.arn
}

output "app_log_group_name" {
  description = "CloudWatch log group name for Supabase application logs"
  value       = aws_cloudwatch_log_group.supabase_app.name
}
