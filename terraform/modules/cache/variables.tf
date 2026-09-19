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
