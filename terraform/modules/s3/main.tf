# ==============================================================================
# S3 Module
# Creates S3 bucket for Supabase file storage
# Encryption, versioning, and access controls enabled by default
# Public access blocked — all access via Supabase storage API only
# ==============================================================================

# ------------------------------------------------------------------------------
# KMS Key for S3 encryption
# Customer managed key for full control over encryption
# ------------------------------------------------------------------------------
resource "aws_kms_key" "s3" {
  description             = "KMS key for Supabase S3 storage bucket encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-s3-kms"
  })
}

resource "aws_kms_alias" "s3" {
  name          = "alias/${var.name_prefix}-s3"
  target_key_id = aws_kms_key.s3.key_id
}

# ------------------------------------------------------------------------------
# S3 Bucket
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "storage" {
  bucket = local.bucket_name

  tags = merge(var.tags, {
    Name    = local.bucket_name
    Purpose = "supabase-file-storage"
  })
}

# ------------------------------------------------------------------------------
# Block all public access
# All access must go through Supabase storage API
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "storage" {
  bucket = aws_s3_bucket.storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# Enable versioning
# Protects against accidental deletion and overwrites
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "storage" {
  bucket = aws_s3_bucket.storage.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ------------------------------------------------------------------------------
# Server-side encryption using customer managed KMS key
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "storage" {
  bucket = aws_s3_bucket.storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.s3.arn
    }
    bucket_key_enabled = true # Reduces KMS API calls and costs
  }
}

# ------------------------------------------------------------------------------
# Lifecycle rules
# Automatically manage storage costs by transitioning old versions
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "storage" {
  bucket = aws_s3_bucket.storage.id

  rule {
    id     = "transition-old-versions"
    status = "Enabled"

    filter {}

    # Move non-current versions to cheaper storage after 30 days
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    # Delete non-current versions after 90 days
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

# ------------------------------------------------------------------------------
# CORS configuration
# Required for browser-based file uploads via Supabase JS client
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_cors_configuration" "storage" {
  bucket = aws_s3_bucket.storage.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = ["*"] # Restrict to your domain in production
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# ------------------------------------------------------------------------------
# IAM Policy for Supabase storage pod access via IRSA
# Least privilege - only allows access to this specific bucket
# ------------------------------------------------------------------------------
resource "aws_iam_policy" "s3_access" {
  name        = "${var.name_prefix}-s3-access"
  description = "Allows Supabase storage pod to access the storage S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          aws_s3_bucket.storage.arn,
          "${aws_s3_bucket.storage.arn}/*"
        ]
      },
      {
        Sid    = "AllowKMSAccess"
        Effect = "Allow"
        Action = [
          "kms:GenerateDataKey",
          "kms:Decrypt"
        ]
        Resource = [aws_kms_key.s3.arn]
      }
    ]
  })

  tags = var.tags
}
