mock_provider "aws" {
  mock_resource "aws_db_subnet_group" {
    defaults = {
      arn  = "arn:aws:rds:us-east-1:123456789012:subgrp:garageflow-test-subnets"
      id   = "garageflow-test-subnets"
      name = "garageflow-test-subnets"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-0dababa5"
      id  = "sg-0dababa5"
    }
  }

  mock_resource "aws_db_instance" {
    defaults = {
      address = "garageflow-test.abcdefghijkl.us-east-1.rds.amazonaws.com"
      arn     = "arn:aws:rds:us-east-1:123456789012:db:garageflow-test"
      id      = "garageflow-test"
      port    = 5432
    }
  }

  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:garageflow/test/database-abc123"
      id  = "arn:aws:secretsmanager:us-east-1:123456789012:secret:garageflow/test/database-abc123"
    }
  }
}

mock_provider "random" {
  mock_resource "random_password" {
    defaults = {
      result = "Test-only-password-123!"
    }
  }
}

variables {
  environment = "homologation"
  owner       = "garageflow-team"
  expires_on  = "2026-09-30"

  platform_contract = {
    schemaVersion = "1.0"
    environment   = "homologation"
    producer      = "platform"
    sourceCommit  = "0123456789abcdef0123456789abcdef01234567"
    publishedAt   = "2026-09-11T12:00:00Z"
    outputs = {
      awsRegion                   = "us-east-1"
      vpcId                       = "vpc-0123456789abcdef0"
      publicSubnetIds             = ["subnet-00000000000000001", "subnet-00000000000000002"]
      privateApplicationSubnetIds = ["subnet-00000000000000003", "subnet-00000000000000004"]
      databaseSubnetIds           = ["subnet-00000000000000005", "subnet-00000000000000006"]
      clusterName                 = "garageflow-homologation"
      clusterSecurityGroupId      = "sg-0123456789abcdef0"
      ecrRepositoryUrl            = "123456789012.dkr.ecr.us-east-1.amazonaws.com/garageflow-homologation"
      apiGatewayId                = "abcdefghij"
      apiGatewayExecutionArn      = "arn:aws:execute-api:us-east-1:123456789012:abcdefghij"
      jwtSecretArn                = "arn:aws:secretsmanager:us-east-1:123456789012:secret:garageflow/homologation/jwt-abc123"
      internalAuthSecretArn       = "arn:aws:secretsmanager:us-east-1:123456789012:secret:garageflow/homologation/internal-auth-abc123"
      bootstrapSecretArn          = "arn:aws:secretsmanager:us-east-1:123456789012:secret:garageflow/homologation/bootstrap-abc123"
      webhookSecretArn            = "arn:aws:secretsmanager:us-east-1:123456789012:secret:garageflow/homologation/webhook-abc123"
      snsTopicArn                 = "arn:aws:sns:us-east-1:123456789012:garageflow-homologation"
    }
  }
}

run "homologation_is_private_and_isolated" {
  command = plan

  assert {
    condition     = module.rds.identifier == "garageflow-homologation"
    error_message = "The RDS identifier must isolate the homologation environment."
  }

  assert {
    condition     = module.rds.publicly_accessible == false && module.rds.multi_az == false
    error_message = "The Academy database must be private and explicitly Single-AZ."
  }

  assert {
    condition     = module.rds.allowed_security_group_id == "sg-0123456789abcdef0"
    error_message = "PostgreSQL ingress must reference only the platform cluster security group."
  }

  assert {
    condition     = module.rds.database_secret_name == "garageflow/homologation/database"
    error_message = "The database repository must own an environment-scoped database secret."
  }

  assert {
    condition     = toset(module.rds.database_secret_keys) == toset(["database", "password", "username"])
    error_message = "The application-compatible database secret must contain only database, password, and username."
  }

  assert {
    condition = (
      toset(keys(output.deployment_outputs)) == toset([
        "databaseHost",
        "databasePort",
        "databaseName",
        "databaseSecretArn",
        "databaseSecurityGroupId",
      ]) &&
      output.deployment_outputs.databasePort == 5432 &&
      output.deployment_outputs.databaseName == "garageflow"
    )
    error_message = "The deployment output must exactly match the public database manifest metadata."
  }
}

run "production_preserves_database" {
  command = plan

  variables {
    environment               = "production"
    final_snapshot_identifier = "garageflow-production-final-reviewed"
    platform_contract = {
      schemaVersion = "1.0"
      environment   = "production"
      producer      = "platform"
      sourceCommit  = "0123456789abcdef0123456789abcdef01234567"
      publishedAt   = "2026-09-11T12:00:00Z"
      outputs = {
        awsRegion                   = "us-east-1"
        vpcId                       = "vpc-0123456789abcdef0"
        publicSubnetIds             = ["subnet-00000000000000001", "subnet-00000000000000002"]
        privateApplicationSubnetIds = ["subnet-00000000000000003", "subnet-00000000000000004"]
        databaseSubnetIds           = ["subnet-00000000000000005", "subnet-00000000000000006"]
        clusterName                 = "garageflow-production"
        clusterSecurityGroupId      = "sg-0123456789abcdef0"
        ecrRepositoryUrl            = "123456789012.dkr.ecr.us-east-1.amazonaws.com/garageflow-production"
        apiGatewayId                = "abcdefghij"
        apiGatewayExecutionArn      = "arn:aws:execute-api:us-east-1:123456789012:abcdefghij"
        jwtSecretArn                = "arn:aws:secretsmanager:us-east-1:123456789012:secret:garageflow/production/jwt-abc123"
        internalAuthSecretArn       = "arn:aws:secretsmanager:us-east-1:123456789012:secret:garageflow/production/internal-auth-abc123"
        bootstrapSecretArn          = "arn:aws:secretsmanager:us-east-1:123456789012:secret:garageflow/production/bootstrap-abc123"
        webhookSecretArn            = "arn:aws:secretsmanager:us-east-1:123456789012:secret:garageflow/production/webhook-abc123"
        snsTopicArn                 = "arn:aws:sns:us-east-1:123456789012:garageflow-production"
      }
    }
  }

  assert {
    condition = (
      module.rds.deletion_protection == true &&
      module.rds.skip_final_snapshot == false &&
      module.rds.final_snapshot_identifier == "garageflow-production-final-reviewed"
    )
    error_message = "Production must enable deletion protection and retain a reviewed final snapshot."
  }
}

run "rejects_platform_environment_mismatch" {
  command = plan

  variables {
    environment = "production"
  }

  expect_failures = [var.platform_contract]
}

run "rejects_platform_producer_mismatch" {
  command = plan

  variables {
    platform_contract = {
      schemaVersion = "1.0"
      environment   = "homologation"
      producer      = "database"
      sourceCommit  = "0123456789abcdef0123456789abcdef01234567"
      publishedAt   = "2026-09-11T12:00:00Z"
      outputs = {
        awsRegion                   = "us-east-1"
        vpcId                       = "vpc-0123456789abcdef0"
        publicSubnetIds             = ["subnet-00000000000000001", "subnet-00000000000000002"]
        privateApplicationSubnetIds = ["subnet-00000000000000003", "subnet-00000000000000004"]
        databaseSubnetIds           = ["subnet-00000000000000005", "subnet-00000000000000006"]
        clusterName                 = "garageflow-homologation"
        clusterSecurityGroupId      = "sg-0123456789abcdef0"
        ecrRepositoryUrl            = "123456789012.dkr.ecr.us-east-1.amazonaws.com/garageflow-homologation"
        apiGatewayId                = "abcdefghij"
        apiGatewayExecutionArn      = "arn:aws:execute-api:us-east-1:123456789012:abcdefghij"
        jwtSecretArn                = "arn:aws:secretsmanager:us-east-1:123456789012:secret:garageflow/homologation/jwt-abc123"
        internalAuthSecretArn       = "arn:aws:secretsmanager:us-east-1:123456789012:secret:garageflow/homologation/internal-auth-abc123"
        bootstrapSecretArn          = "arn:aws:secretsmanager:us-east-1:123456789012:secret:garageflow/homologation/bootstrap-abc123"
        webhookSecretArn            = "arn:aws:secretsmanager:us-east-1:123456789012:secret:garageflow/homologation/webhook-abc123"
        snsTopicArn                 = "arn:aws:sns:us-east-1:123456789012:garageflow-homologation"
      }
    }
  }

  expect_failures = [var.platform_contract]
}
