# ==============================================================================
# Secrets Module Outputs
# ==============================================================================

output "secret_arns" {
  description = "ARNs of all Supabase secrets in Secrets Manager"
  value = {
    db        = aws_secretsmanager_secret.db.arn
    jwt       = aws_secretsmanager_secret.jwt.arn
    dashboard = aws_secretsmanager_secret.dashboard.arn
    analytics = aws_secretsmanager_secret.analytics.arn
    realtime  = aws_secretsmanager_secret.realtime.arn
    meta      = aws_secretsmanager_secret.meta.arn
  }
}

output "secret_names" {
  description = "Names of all secrets in Secrets Manager - used by ESO SecretStore"
  value       = local.secret_names
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for secrets encryption"
  value       = aws_kms_key.secrets.arn
}

output "eso_policy_arn" {
  description = "ARN of the IAM policy for ESO to read secrets - attached to ESO IRSA role"
  value       = aws_iam_policy.eso_secrets_access.arn
}
