variable "identifier" {
  description = "Stable identifier for the RDS instance and related resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.identifier)) && !strcontains(var.identifier, "--")
    error_message = "identifier must be a valid lowercase RDS identifier between 2 and 63 characters."
  }
}

variable "vpc_id" {
  description = "ID of the platform-owned VPC that hosts the database."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must be a syntactically valid VPC ID."
  }
}

variable "database_subnet_ids" {
  description = "Exactly two distinct platform-owned database subnet IDs."
  type        = list(string)

  validation {
    condition = (
      length(var.database_subnet_ids) == 2 &&
      length(distinct(var.database_subnet_ids)) == 2 &&
      alltrue([for subnet_id in var.database_subnet_ids : can(regex("^subnet-[0-9a-f]+$", subnet_id))])
    )
    error_message = "database_subnet_ids must contain exactly two distinct, syntactically valid subnet IDs."
  }
}

variable "cluster_security_group_id" {
  description = "Platform EKS cluster security group allowed to connect to PostgreSQL."
  type        = string

  validation {
    condition     = can(regex("^sg-[0-9a-f]+$", var.cluster_security_group_id))
    error_message = "cluster_security_group_id must be a syntactically valid security group ID."
  }
}

variable "database_secret_name" {
  description = "Environment-scoped Secrets Manager name for the database credentials."
  type        = string

  validation {
    condition     = can(regex("^garageflow/(homologation|production)/database$", var.database_secret_name))
    error_message = "database_secret_name must use garageflow/{environment}/database."
  }
}

variable "deletion_protection" {
  description = "Whether RDS deletion protection is enabled."
  type        = bool
  default     = true
}

variable "final_snapshot_identifier" {
  description = "Final snapshot retained when an explicitly authorized deletion occurs."
  type        = string
}

variable "secret_recovery_window_in_days" {
  description = "Secrets Manager recovery window; zero is reserved for explicitly reviewed teardown."
  type        = number
  default     = 7

  validation {
    condition     = contains([0, 7], var.secret_recovery_window_in_days)
    error_message = "secret_recovery_window_in_days must be 0 or 7."
  }
}

variable "tags" {
  description = "Non-sensitive tags applied to database resources."
  type        = map(string)
  default     = {}
}
