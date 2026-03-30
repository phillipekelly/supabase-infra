# ==============================================================================
# RDS Module Outputs
# ==============================================================================

output "cluster_endpoint" {
  description = "Writer endpoint for the Aurora cluster (use for read/write)"
  value       = aws_rds_cluster.main.endpoint
}

output "cluster_reader_endpoint" {
  description = "Reader endpoint for the Aurora cluster (use for read-only)"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "cluster_identifier" {
  description = "Identifier of the Aurora cluster"
  value       = aws_rds_cluster.main.cluster_identifier
}

output "cluster_port" {
  description = "Port the Aurora cluster is listening on"
  value       = aws_rds_cluster.main.port
}

output "security_group_id" {
  description = "Security group ID of the RDS cluster"
  value       = aws_security_group.rds.id
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = aws_kms_key.rds.arn
}

output "db_name" {
  description = "Name of the database"
  value       = aws_rds_cluster.main.database_name
}

output "supabase_database_name" {
  description = "Name of the _supabase database created for analytics"
  value       = "_supabase"
}
