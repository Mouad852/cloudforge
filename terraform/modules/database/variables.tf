variable "environment" {
  description = "Environment name (dev or prod), used in resource naming/tags"
  type        = string
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
