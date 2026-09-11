output "deployment_outputs" {
  description = "Public metadata used to build the database infrastructure contract."
  value = {
    databaseHost            = module.rds.endpoint
    databasePort            = module.rds.port
    databaseName            = module.rds.database_name
    databaseSecretArn       = module.rds.database_secret_arn
    databaseSecurityGroupId = module.rds.security_group_id
  }
}
