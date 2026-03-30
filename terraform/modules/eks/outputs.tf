# ==============================================================================
# EKS Module Outputs
# ==============================================================================

output "cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Endpoint URL of the EKS cluster API server"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64 encoded certificate authority data for the cluster"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = aws_eks_cluster.main.version
}

output "node_security_group_id" {
  description = "Security group ID of EKS worker nodes - used by RDS security group"
  value       = aws_security_group.nodes.id
}

output "oidc_provider_arn" {
  description = "ARN of the OIDC provider - used for IRSA role trust policies"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_issuer" {
  description = "OIDC issuer URL without https:// prefix"
  value       = local.oidc_issuer
}

output "eso_role_arn" {
  description = "ARN of the IRSA role for External Secrets Operator"
  value       = aws_iam_role.eso.arn
}

output "storage_role_arn" {
  description = "ARN of the IRSA role for Supabase storage pod"
  value       = aws_iam_role.storage.arn
}

output "node_role_arn" {
  description = "ARN of the IAM role for EKS worker nodes"
  value       = aws_iam_role.nodes.arn
}

output "karpenter_role_arn" {
  description = "ARN of the IRSA role for Karpenter"
  value       = aws_iam_role.karpenter.arn
}

output "alb_controller_role_arn" {
  description = "ARN of the IRSA role for AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller.arn
}

output "cluster_security_group_id" {
  description = "EKS cluster security group ID — attached to all nodes by EKS automatically"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}
