# ==============================================================================
# S3 Module Outputs
# ==============================================================================

output "bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.storage.id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.storage.arn
}

output "bucket_regional_domain_name" {
  description = "Regional domain name of the S3 bucket"
  value       = aws_s3_bucket.storage.bucket_regional_domain_name
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for bucket encryption"
  value       = aws_kms_key.s3.arn
}

output "s3_access_policy_arn" {
  description = "ARN of the IAM policy for S3 access - attached to storage pod IRSA role"
  value       = aws_iam_policy.s3_access.arn
}
