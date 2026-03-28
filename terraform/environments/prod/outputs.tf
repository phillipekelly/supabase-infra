# ==============================================================================
# Environment Outputs
# Printed after successful terraform apply
# Use these for smoke testing and verification
# ==============================================================================

output "eks_cluster_name" {
  description = "EKS cluster name - use with kubectl and aws eks update-kubeconfig"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "aurora_endpoint" {
  description = "Aurora PostgreSQL writer endpoint"
  value       = module.rds.cluster_endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora PostgreSQL reader endpoint"
  value       = module.rds.cluster_reader_endpoint
}

output "storage_bucket_name" {
  description = "S3 bucket name for Supabase storage"
  value       = module.s3.bucket_name
}

output "supabase_url" {
  description = "Supabase API URL via Kong"
  value       = "https://${var.supabase_domain}"
}

output "studio_url" {
  description = "Supabase Studio URL"
  value       = "https://${var.studio_domain}"
}

output "configure_kubectl" {
  description = "Command to configure kubectl for this cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}
