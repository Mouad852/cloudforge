variable "environment" {
  description = "Environment name (dev, prod, or test), used in resource naming/tags"
  type        = string

  validation {
    condition     = contains(["dev", "prod", "test"], var.environment)
    error_message = "environment must be one of: dev, prod, test."
  }
}

variable "name_prefix" {
  description = "Prefix for every resource name and the Secrets Manager path (<prefix>/<environment>/redis-auth). modules/compute's IAM policy expects the default, so only change it when not using that module."
  type        = string
  default     = "cloudforge"

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name_prefix)) && length(var.name_prefix) <= 28
    error_message = "name_prefix must be lowercase letters, digits and single hyphens, start with a letter, not end with a hyphen, and be at most 28 characters - it becomes part of the ElastiCache replication group ID, which allows no other characters and at most 40."
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
  description = "Route 53 private hosted zone ID the DNS record lives in (ADR-013) - only needed when dns_record_name is set"
  type        = string
  default     = null
}

variable "dns_record_name" {
  description = "Fully qualified name of a private CNAME pointing at the Redis primary endpoint (for example cache.example.internal). Null, the default, creates no record."
  type        = string
  default     = null

  validation {
    condition     = var.dns_record_name == null || can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.dns_record_name))
    error_message = "dns_record_name must be a lowercase fully qualified name such as cache.example.internal."
  }

  validation {
    condition     = var.dns_record_name == null || var.private_zone_id != null
    error_message = "private_zone_id is required when dns_record_name is set - the record has to live in a hosted zone."
  }
}

variable "node_type" {
  description = "ElastiCache node type"
  type        = string
  default     = "cache.t4g.micro"

  validation {
    condition     = startswith(var.node_type, "cache.")
    error_message = "node_type must be an ElastiCache node type starting with \"cache.\" (for example cache.t4g.micro), not an EC2 or RDS type."
  }
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

variable "dns_ttl_seconds" {
  description = "TTL, in seconds, of the private DNS CNAME the app connects through - short enough that a replaced Redis endpoint is picked up quickly"
  type        = number
  default     = 300

  validation {
    condition     = var.dns_ttl_seconds >= 0 && var.dns_ttl_seconds <= 86400
    error_message = "dns_ttl_seconds must be between 0 and 86400 (one day)."
  }
}
