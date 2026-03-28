# ==============================================================================
# AWS Secrets Manager Module
# Creates and populates all Supabase secrets in AWS Secrets Manager
# Secrets are consumed by External Secrets Operator running in EKS
# No secret values are stored in Terraform state or version control
# ==============================================================================

# ------------------------------------------------------------------------------
# KMS Key for Secrets Manager encryption
# All secrets encrypted with customer managed key
# ------------------------------------------------------------------------------
resource "aws_kms_key" "secrets" {
  description             = "KMS key for Supabase secrets encryption in Secrets Manager"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-secrets-kms"
  })
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${var.name_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# ------------------------------------------------------------------------------
# Database Secret
# Contains Aurora connection credentials
# ------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db" {
  name        = local.secret_names.db
  description = "Aurora PostgreSQL credentials for Supabase services"
  kms_key_id  = aws_kms_key.secrets.arn

  # Prevent accidental deletion
  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name      = local.secret_names.db
    Component = "database"
  })
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    username = var.db_master_username
    password = var.db_master_password
    database = var.db_name
  })
}

# ------------------------------------------------------------------------------
# JWT Secret
# Contains JWT signing keys for Supabase auth
# ------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "jwt" {
  name        = local.secret_names.jwt
  description = "JWT signing keys for Supabase authentication"
  kms_key_id  = aws_kms_key.secrets.arn

  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name      = local.secret_names.jwt
    Component = "auth"
  })
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id = aws_secretsmanager_secret.jwt.id

  secret_string = jsonencode({
    anonKey    = var.jwt_anon_key
    serviceKey = var.jwt_service_key
    secret     = var.jwt_secret
  })
}

# ------------------------------------------------------------------------------
# Dashboard Secret
# Contains Supabase Studio login credentials
# ------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "dashboard" {
  name        = local.secret_names.dashboard
  description = "Supabase Studio dashboard credentials"
  kms_key_id  = aws_kms_key.secrets.arn

  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name      = local.secret_names.dashboard
    Component = "studio"
  })
}

resource "aws_secretsmanager_secret_version" "dashboard" {
  secret_id = aws_secretsmanager_secret.dashboard.id

  secret_string = jsonencode({
    username    = var.dashboard_username
    password    = var.dashboard_password
    openAiApiKey = "placeholder"
  })
}

# ------------------------------------------------------------------------------
# Analytics Secret
# Contains Logflare access tokens
# ------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "analytics" {
  name        = local.secret_names.analytics
  description = "Logflare analytics access tokens"
  kms_key_id  = aws_kms_key.secrets.arn

  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name      = local.secret_names.analytics
    Component = "analytics"
  })
}

resource "aws_secretsmanager_secret_version" "analytics" {
  secret_id = aws_secretsmanager_secret.analytics.id

  secret_string = jsonencode({
    publicAccessToken  = var.analytics_public_token
    privateAccessToken = var.analytics_private_token
  })
}

# ------------------------------------------------------------------------------
# Realtime Secret
# Contains Supabase Realtime secret key base
# ------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "realtime" {
  name        = local.secret_names.realtime
  description = "Supabase Realtime secret key base"
  kms_key_id  = aws_kms_key.secrets.arn

  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name      = local.secret_names.realtime
    Component = "realtime"
  })
}

resource "aws_secretsmanager_secret_version" "realtime" {
  secret_id = aws_secretsmanager_secret.realtime.id

  secret_string = jsonencode({
    secretKeyBase = var.realtime_secret_key_base
  })
}

# ------------------------------------------------------------------------------
# Meta Secret
# Contains Supabase Meta crypto key
# ------------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "meta" {
  name        = local.secret_names.meta
  description = "Supabase Meta service crypto key"
  kms_key_id  = aws_kms_key.secrets.arn

  recovery_window_in_days = 7

  tags = merge(var.tags, {
    Name      = local.secret_names.meta
    Component = "meta"
  })
}

resource "aws_secretsmanager_secret_version" "meta" {
  secret_id = aws_secretsmanager_secret.meta.id

  secret_string = jsonencode({
    cryptoKey = var.meta_crypto_key
  })
}

# ------------------------------------------------------------------------------
# IAM Policy for ESO to read secrets
# Least privilege - read only access to Supabase secrets only
# Attached to ESO IRSA role in EKS module
# ------------------------------------------------------------------------------
resource "aws_iam_policy" "eso_secrets_access" {
  name        = "${var.name_prefix}-eso-secrets-access"
  description = "Allows External Secrets Operator to read Supabase secrets from Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSecretsManagerRead"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          aws_secretsmanager_secret.db.arn,
          aws_secretsmanager_secret.jwt.arn,
          aws_secretsmanager_secret.dashboard.arn,
          aws_secretsmanager_secret.analytics.arn,
          aws_secretsmanager_secret.realtime.arn,
          aws_secretsmanager_secret.meta.arn
        ]
      },
      {
        Sid    = "AllowKMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = [aws_kms_key.secrets.arn]
      }
    ]
  })

  tags = var.tags
}
