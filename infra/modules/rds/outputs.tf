output "endpoint" {
  description = "RDS endpoint hostname without a port or credentials."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "PostgreSQL port exposed inside the VPC."
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Name of the GarageFlow PostgreSQL database."
  value       = local.database_name
}

output "database_secret_arn" {
  description = "ARN of the database credential secret; no secret value is exposed."
  value       = aws_secretsmanager_secret.database.arn
}

output "security_group_id" {
  description = "ID of the database security group."
  value       = aws_security_group.database.id
}

output "identifier" {
  description = "Stable environment-specific RDS identifier."
  value       = aws_db_instance.this.identifier
}

output "publicly_accessible" {
  description = "Private-access invariant exposed for root-level policy tests."
  value       = aws_db_instance.this.publicly_accessible
}

output "multi_az" {
  description = "Explicit Academy sizing exposed for root-level policy tests."
  value       = aws_db_instance.this.multi_az
}

output "allowed_security_group_id" {
  description = "Only source security group allowed by the PostgreSQL ingress rule."
  value       = aws_vpc_security_group_ingress_rule.postgres_from_eks.referenced_security_group_id
}

output "database_secret_name" {
  description = "Environment-scoped secret name exposed for root-level policy tests."
  value       = aws_secretsmanager_secret.database.name
}

output "database_secret_keys" {
  description = "Non-sensitive key names in the application-compatible secret JSON object."
  value       = keys(local.secret_payload)
}

output "deletion_protection" {
  description = "Deletion protection policy exposed for root-level policy tests."
  value       = aws_db_instance.this.deletion_protection
}

output "skip_final_snapshot" {
  description = "Final snapshot retention policy exposed for root-level policy tests."
  value       = aws_db_instance.this.skip_final_snapshot
}

output "final_snapshot_identifier" {
  description = "Reviewed final snapshot identifier exposed for root-level policy tests."
  value       = aws_db_instance.this.final_snapshot_identifier
}
