# ==============================================================================
# RDS Aurora PostgreSQL Module
# Creates Aurora PostgreSQL cluster with Multi-AZ for high availability
# Database is placed in private subnets with no public access
# Automated backups and encryption enabled by default
# ==============================================================================

# ------------------------------------------------------------------------------
# Security Group
# Only allows inbound connections from EKS worker nodes
# Database is completely unreachable from the internet
# ------------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name_prefix = "${var.name_prefix}-rds-"
  description = "Security group for Aurora PostgreSQL - allows inbound from EKS only"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = local.port
    to_port         = local.port
    protocol        = "tcp"
    security_groups = [var.eks_security_group_id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rds-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------------------
# DB Subnet Group
# Defines which subnets Aurora can use
# Must span at least 2 AZs for Multi-AZ support
# ------------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name        = "${var.name_prefix}-subnet-group"
  description = "Subnet group for Aurora PostgreSQL across multiple AZs"
  subnet_ids  = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-db-subnet-group"
  })
}

# ------------------------------------------------------------------------------
# KMS Key for encryption at rest
# Customer managed key gives full control over key rotation and access
# ------------------------------------------------------------------------------
resource "aws_kms_key" "rds" {
  description             = "KMS key for Aurora PostgreSQL encryption at rest"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rds-kms"
  })
}

resource "aws_kms_alias" "rds" {
  name          = "alias/${var.name_prefix}-rds"
  target_key_id = aws_kms_key.rds.key_id
}

# ------------------------------------------------------------------------------
# Aurora PostgreSQL Cluster
# Multi-AZ with automated backups and encryption
# deletion_protection prevents accidental destruction
# ------------------------------------------------------------------------------
resource "aws_rds_cluster" "main" {
  cluster_identifier = local.cluster_identifier

  # Engine
  engine         = "aurora-postgresql"
  engine_version = "15.4"
  port           = local.port

  # Database
  database_name   = var.db_name
  master_username = var.db_master_username
  master_password = var.db_master_password

  # Networking
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  availability_zones     = var.availability_zones

  # High availability
  storage_type = "aurora"

  # Backup and maintenance
  backup_retention_period   = var.db_backup_retention_days
  preferred_backup_window   = "02:00-03:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot     = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.cluster_identifier}-final-snapshot"

  # Security
  storage_encrypted = true
  kms_key_id       = aws_kms_key.rds.arn
  deletion_protection = true

  # Apply changes immediately in production
  apply_immediately = false

  tags = merge(var.tags, {
    Name = local.cluster_identifier
  })
}

# ------------------------------------------------------------------------------
# Aurora Cluster Instances
# One primary + one replica across different AZs
# Replica automatically becomes primary if primary AZ fails
# ------------------------------------------------------------------------------

# Primary instance in first AZ
resource "aws_rds_cluster_instance" "primary" {
  identifier         = "${local.cluster_identifier}-primary"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.db_instance_class
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  availability_zone      = var.availability_zones[0]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  publicly_accessible    = false

  # Performance Insights for query monitoring
  performance_insights_enabled = true
  performance_insights_kms_key_id = aws_kms_key.rds.arn
  performance_insights_retention_period = 7

  tags = merge(var.tags, {
    Name = "${local.cluster_identifier}-primary"
    Role = "primary"
  })
}

# Replica instance in second AZ
# Automatic failover target if primary fails
resource "aws_rds_cluster_instance" "replica" {
  identifier         = "${local.cluster_identifier}-replica"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.db_instance_class
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  availability_zone      = var.availability_zones[1]
  db_subnet_group_name   = aws_db_subnet_group.main.name
  publicly_accessible    = false

  # Performance Insights for query monitoring
  performance_insights_enabled = true
  performance_insights_kms_key_id = aws_kms_key.rds.arn
  performance_insights_retention_period = 7

  tags = merge(var.tags, {
    Name = "${local.cluster_identifier}-replica"
    Role = "replica"
  })
}

# ------------------------------------------------------------------------------
# Aurora Database Bootstrap
# Creates all required Supabase roles, schemas, and extensions
# Replaces manual SQL script execution
# Requires postgresql provider configured with Aurora endpoint
# ------------------------------------------------------------------------------

# Create _supabase database
resource "postgresql_database" "supabase" {
  name  = "_supabase"
  owner = var.db_master_username

  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_rds_cluster_instance.replica
  ]
}

# ------------------------------------------------------------------------------
# Extensions
# ------------------------------------------------------------------------------
resource "postgresql_extension" "pgcrypto" {
  name   = "pgcrypto"
  schema = "extensions"

  depends_on = [postgresql_schema.extensions]
}

resource "postgresql_extension" "uuid_ossp" {
  name   = "uuid-ossp"
  schema = "extensions"

  depends_on = [postgresql_schema.extensions]
}

resource "postgresql_extension" "pg_stat_statements" {
  name   = "pg_stat_statements"
  schema = "extensions"

  depends_on = [postgresql_schema.extensions]
}

resource "postgresql_extension" "pgjwt" {
  name   = "pgjwt"
  schema = "extensions"

  depends_on = [postgresql_schema.extensions]
}

# ------------------------------------------------------------------------------
# Roles
# ------------------------------------------------------------------------------
resource "postgresql_role" "anon" {
  name      = "anon"
  login     = false
  inherit = false
}

resource "postgresql_role" "authenticated" {
  name      = "authenticated"
  login     = false
  inherit = false
}

resource "postgresql_role" "service_role" {
  name       = "service_role"
  login      = false
  inherit = false
  bypass_row_level_security = true
}

resource "postgresql_role" "authenticator" {
  name      = "authenticator"
  login     = true
  inherit = false
  password  = var.db_master_password
}

resource "postgresql_role" "dashboard_user" {
  name       = "dashboard_user"
  login      = false
  create_role = true
  create_database = true
}

resource "postgresql_role" "pgbouncer" {
  name     = "pgbouncer"
  login    = true
  password = var.db_master_password
}

resource "postgresql_role" "supabase_auth_admin" {
  name        = "supabase_auth_admin"
  login       = true
  inherit = false
  create_role = true
  password    = var.db_master_password
}

resource "postgresql_role" "supabase_storage_admin" {
  name        = "supabase_storage_admin"
  login       = true
  inherit = false
  create_role = true
  password    = var.db_master_password
}

resource "postgresql_role" "supabase_read_only_user" {
  name                      = "supabase_read_only_user"
  login                     = true
  bypass_row_level_security = true
  password                  = var.db_master_password
}

resource "postgresql_role" "supabase_replication_admin" {
  name        = "supabase_replication_admin"
  login       = true
  replication = true
  password    = var.db_master_password
}

# ------------------------------------------------------------------------------
# Role Memberships
# ------------------------------------------------------------------------------
resource "postgresql_grant_role" "authenticator_anon" {
  role       = postgresql_role.authenticator.name
  grant_role = postgresql_role.anon.name
}

resource "postgresql_grant_role" "authenticator_authenticated" {
  role       = postgresql_role.authenticator.name
  grant_role = postgresql_role.authenticated.name
}

resource "postgresql_grant_role" "authenticator_service_role" {
  role       = postgresql_role.authenticator.name
  grant_role = postgresql_role.service_role.name
}

resource "postgresql_grant_role" "storage_admin_authenticator" {
  role       = postgresql_role.supabase_storage_admin.name
  grant_role = postgresql_role.authenticator.name
}

# ------------------------------------------------------------------------------
# Schemas in postgres database
# ------------------------------------------------------------------------------
resource "postgresql_schema" "extensions" {
  name  = "extensions"
  owner = var.db_master_username
}

resource "postgresql_schema" "auth" {
  name  = "auth"
  owner = postgresql_role.supabase_auth_admin.name

  depends_on = [postgresql_role.supabase_auth_admin]
}

resource "postgresql_schema" "storage" {
  name  = "storage"
  owner = postgresql_role.supabase_storage_admin.name

  depends_on = [postgresql_role.supabase_storage_admin]
}

resource "postgresql_schema" "realtime" {
  name  = "realtime"
  owner = var.db_master_username
}

resource "postgresql_schema" "_realtime" {
  name  = "_realtime"
  owner = var.db_master_username
}

resource "postgresql_schema" "graphql_public" {
  name  = "graphql_public"
  owner = var.db_master_username
}

resource "postgresql_schema" "vault" {
  name  = "vault"
  owner = var.db_master_username
}

# ------------------------------------------------------------------------------
# Schema in _supabase database
# ------------------------------------------------------------------------------
resource "postgresql_schema" "_analytics" {
  name     = "_analytics"
  owner    = var.db_master_username
  database = postgresql_database.supabase.name

  depends_on = [postgresql_database.supabase]
}

# ------------------------------------------------------------------------------
# Grants
# ------------------------------------------------------------------------------
resource "postgresql_grant" "public_anon" {
  database    = "postgres"
  role        = postgresql_role.anon.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["USAGE"]
}

resource "postgresql_grant" "public_authenticated" {
  database    = "postgres"
  role        = postgresql_role.authenticated.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["USAGE"]
}

resource "postgresql_grant" "public_service_role" {
  database    = "postgres"
  role        = postgresql_role.service_role.name
  schema      = "public"
  object_type = "schema"
  privileges  = ["USAGE"]
}

resource "postgresql_grant" "extensions_anon" {
  database    = "postgres"
  role        = postgresql_role.anon.name
  schema      = "extensions"
  object_type = "schema"
  privileges  = ["USAGE"]
}

resource "postgresql_grant" "extensions_authenticated" {
  database    = "postgres"
  role        = postgresql_role.authenticated.name
  schema      = "extensions"
  object_type = "schema"
  privileges  = ["USAGE"]
}

resource "postgresql_grant" "extensions_service_role" {
  database    = "postgres"
  role        = postgresql_role.service_role.name
  schema      = "extensions"
  object_type = "schema"
  privileges  = ["USAGE"]
}

# ------------------------------------------------------------------------------
# Search Path
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Set search path for supabase_admin via postgresql_grant
# postgresql_alter_role is not supported - use null_resource instead
# ------------------------------------------------------------------------------
resource "null_resource" "supabase_admin_search_path" {
  provisioner "local-exec" {
    command = <<-EOT
      PGPASSWORD='${var.db_master_password}' psql \
        "sslmode=require host=${aws_rds_cluster.main.endpoint} \
        user=${var.db_master_username} dbname=postgres" \
        -c "ALTER ROLE ${var.db_master_username} SET search_path TO _realtime, public;"
    EOT
  }

  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_rds_cluster_instance.replica,
    postgresql_schema._realtime
  ]
}
