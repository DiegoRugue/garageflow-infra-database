variable "environment" {
  description = "Deployment environment selected from the protected branch."
  type        = string

  validation {
    condition     = contains(["homologation", "production"], var.environment)
    error_message = "environment must be homologation or production."
  }
}

variable "aws_region" {
  description = "AWS region for all database resources."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "aws_region must be us-east-1."
  }
}

variable "owner" {
  description = "Non-sensitive owner tag used for Academy resource identification."
  type        = string

  validation {
    condition     = trimspace(var.owner) != "" && length(var.owner) <= 128 && !can(regex("[\\x00-\\x1F\\x7F]", var.owner))
    error_message = "owner must be a non-empty value of at most 128 characters without control characters."
  }
}

variable "expires_on" {
  description = "Academy resource expiry date in YYYY-MM-DD format."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", var.expires_on))
    error_message = "expires_on must use YYYY-MM-DD format."
  }
}

variable "platform_contract" {
  description = "Validated platform contract loaded from the versioned S3 metadata manifest."
  type = object({
    schemaVersion = string
    environment   = string
    producer      = string
    sourceCommit  = string
    publishedAt   = string
    outputs = object({
      awsRegion                   = string
      vpcId                       = string
      publicSubnetIds             = list(string)
      privateApplicationSubnetIds = list(string)
      databaseSubnetIds           = list(string)
      clusterName                 = string
      clusterSecurityGroupId      = string
      ecrRepositoryUrl            = string
      apiGatewayId                = string
      apiGatewayExecutionArn      = string
      jwtSecretArn                = string
      internalAuthSecretArn       = string
      bootstrapSecretArn          = string
      webhookSecretArn            = string
      snsTopicArn                 = string
    })
  })

  validation {
    condition     = var.platform_contract.schemaVersion == "1.0"
    error_message = "platform_contract must use schema version 1.0."
  }

  validation {
    condition     = var.platform_contract.producer == "platform"
    error_message = "platform_contract must be produced by platform."
  }

  validation {
    condition     = var.platform_contract.environment == var.environment
    error_message = "platform_contract environment must match environment."
  }

  validation {
    condition     = var.platform_contract.outputs.awsRegion == var.aws_region
    error_message = "platform_contract AWS region must match aws_region."
  }
}

variable "allow_database_destroy" {
  description = "Explicit reviewed switch that disables RDS deletion protection. A final snapshot is still required."
  type        = bool
  default     = false
}

variable "final_snapshot_identifier" {
  description = "Optional reviewed final snapshot identifier. A stable environment name is used when omitted."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.final_snapshot_identifier == null ||
      can(regex("^[a-z][a-z0-9-]{0,253}[a-z0-9]$", var.final_snapshot_identifier))
    )
    error_message = "final_snapshot_identifier must be a valid lowercase RDS snapshot identifier when set."
  }
}
