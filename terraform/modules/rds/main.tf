# ==============================================================================
# RDS Aurora PostgreSQL Module
# Creates Aurora PostgreSQL cluster with Multi-AZ for high availability
# Database is placed in private subnets with no public access
# Bootstrap is handled by a Kubernetes Job inside the cluster (see supabase module)
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
  
  ingress {
  description     = "PostgreSQL from Karpenter-provisioned nodes (node SG)"
  from_port       = local.port
  to_port         = local.port
  protocol        = "tcp"
  security_groups = [var.node_security_group_id]
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
# availability_zones intentionally omitted — Aurora manages its own AZ placement
# Specifying AZs causes drift and forced replacement on every apply
# ------------------------------------------------------------------------------
resource "aws_rds_cluster" "main" {
  cluster_identifier = local.cluster_identifier

  engine         = "aurora-postgresql"
  engine_version = "15.8"
  port           = local.port

  database_name   = var.db_name
  master_username = var.db_master_username
  master_password = var.db_master_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  storage_type = "aurora"

  backup_retention_period      = var.db_backup_retention_days
  preferred_backup_window      = "02:00-03:00"
  preferred_maintenance_window = "sun:04:00-sun:05:00"
  copy_tags_to_snapshot        = true
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${local.cluster_identifier}-final-snapshot"

  storage_encrypted   = true
  deletion_protection = true
  apply_immediately   = false

  tags = merge(var.tags, {
    Name = local.cluster_identifier
  })
}

# ------------------------------------------------------------------------------
# Aurora Cluster Instances
# publicly_accessible = false — bootstrap handled by K8s Job inside cluster
# ------------------------------------------------------------------------------
resource "aws_rds_cluster_instance" "primary" {
  identifier         = "${local.cluster_identifier}-primary"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.db_instance_class
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  db_subnet_group_name = aws_db_subnet_group.main.name
  publicly_accessible  = false

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  tags = merge(var.tags, {
    Name = "${local.cluster_identifier}-primary"
    Role = "primary"
  })
}

resource "aws_rds_cluster_instance" "replica" {
  identifier         = "${local.cluster_identifier}-replica"
  cluster_identifier = aws_rds_cluster.main.id
  instance_class     = var.db_instance_class
  engine             = aws_rds_cluster.main.engine
  engine_version     = aws_rds_cluster.main.engine_version

  db_subnet_group_name = aws_db_subnet_group.main.name
  publicly_accessible  = false

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  tags = merge(var.tags, {
    Name = "${local.cluster_identifier}-replica"
    Role = "replica"
  })
}
