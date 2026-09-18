variable "environment" {
  description = "Environment name (dev, prod, or test), used in resource naming/tags"
  type        = string

  validation {
    condition     = contains(["dev", "prod", "test"], var.environment)
    error_message = "environment must be one of: dev, prod, test."
  }
}

variable "vpc_id" {
  description = "VPC ID the Redis security group lives in"
  type        = string
}

variable "data_subnet_ids" {
  description = "Data-tier subnet IDs (both AZs) for the ElastiCache subnet group"
  type        = list(string)
}

variable "app_security_group_id" {
  description = "App instances' security group ID - the only allowed ingress source"
  type        = string
}

variable "private_zone_id" {
  description = "Route 53 private hosted zone ID (ADR-013) - the DNS record lives here"
  type        = string
}

variable "node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.micro"
}

variable "engine_version" {
  description = "Redis engine version"
  type        = string
  default     = "7.1"
}

variable "apply_immediately" {
  description = "Apply modifications right away instead of waiting for the next maintenance window - on in dev for fast iteration"
  type        = bool
  default     = true
}
