locals {
  identifier                = "garageflow-${var.environment}"
  final_snapshot_identifier = coalesce(var.final_snapshot_identifier, "garageflow-${var.environment}-final")
}

module "rds" {
  source = "../modules/rds"

  identifier                     = local.identifier
  vpc_id                         = var.platform_contract.outputs.vpcId
  database_subnet_ids            = var.platform_contract.outputs.databaseSubnetIds
  cluster_security_group_id      = var.platform_contract.outputs.clusterSecurityGroupId
  database_secret_name           = "garageflow/${var.environment}/database"
  deletion_protection            = !var.allow_database_destroy
  final_snapshot_identifier      = local.final_snapshot_identifier
  secret_recovery_window_in_days = var.allow_database_destroy ? 0 : 7
  tags                           = local.common_tags
}
