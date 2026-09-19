variable "environment" {
  description = "Environment name (dev, prod, or test), used in resource naming/tags"
  type        = string

  validation {
    condition     = contains(["dev", "prod", "test"], var.environment)
    error_message = "environment must be one of: dev, prod, test."
  }
}

variable "vpc_id" {
  description = "VPC ID the RDS security group lives in"
  type        = string
}

variable "data_subnet_ids" {
  description = "Data-tier subnet IDs (both AZs) for the DB subnet group"
  type        = list(string)
}

variable "app_security_group_id" {
  description = "App instances' security group ID - the only allowed ingress source"
  type        = string
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "16.15"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t4g.micro"

  validation {
    condition     = startswith(var.instance_class, "db.")
    error_message = "instance_class must be an RDS class starting with \"db.\" (for example db.t4g.micro), not an EC2 or ElastiCache type."
  }
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20
    error_message = "allocated_storage must be at least 20 GB, the minimum RDS accepts for PostgreSQL on gp2/gp3."
  }
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "cloudstore"
}

variable "master_username" {
  description = "Master username - the password itself is AWS-managed (ADR-009), never set here"
  type        = string
  default     = "cloudforge_admin"
}

variable "multi_az" {
  description = "Multi-AZ deployment - on in prod, off in dev"
  type        = bool
  default     = false
}

variable "deletion_protection" {
  description = "Deletion protection - on in prod, off in dev"
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Automated backup retention in days"
  type        = number
  default     = 1

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 0 and 35 days, RDS's hard limit for automated backups."
  }
}

variable "private_zone_id" {
  description = "Route 53 private hosted zone ID (ADR-013) - the DNS record lives here"
  type        = string
}

variable "snapshot_identifier" {
  description = "Restore from this snapshot instead of creating an empty DB - set to a final snapshot ID to bring data back after a dev-down (ADR-015)"
  type        = string
  default     = null
}

variable "apply_immediately" {
  description = "Apply modifications right away instead of waiting for the next maintenance window - on in dev for fast iteration, should be off in prod to avoid mid-day disruption"
  type        = bool
  default     = true
}

variable "dns_ttl_seconds" {
  description = "TTL, in seconds, of the private DNS CNAME the app connects through - short enough that a replaced RDS instance is picked up quickly"
  type        = number
  default     = 300

  validation {
    condition     = var.dns_ttl_seconds >= 0 && var.dns_ttl_seconds <= 86400
    error_message = "dns_ttl_seconds must be between 0 and 86400 (one day)."
  }
}
