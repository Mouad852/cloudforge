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
}

variable "allocated_storage" {
  description = "Allocated storage in GB"
  type        = number
  default     = 20
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
