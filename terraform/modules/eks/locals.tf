# ==============================================================================
# EKS Module Locals
# ==============================================================================

locals {
  # OIDC issuer URL without https:// prefix - required for IRSA
  oidc_issuer = trimprefix(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://")
}
