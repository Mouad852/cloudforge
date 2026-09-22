variable "environment" {
  description = "Environment name (dev, prod, or test), used in resource naming/tags"
  type        = string

  validation {
    condition     = contains(["dev", "prod", "test"], var.environment)
    error_message = "environment must be one of: dev, prod, test."
  }
}

variable "vpc_id" {
  description = "VPC ID the ALB and its target groups live in"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block - scopes the ALB's egress to app instances instead of 0.0.0.0/0"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public-tier subnet IDs (both AZs) the ALB is deployed into"
  type        = list(string)
}

variable "app_port" {
  description = "Port the app instances listen on"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Shallow health check path the app exposes"
  type        = string
  default     = "/healthz"
}

variable "blue_weight" {
  description = "Percentage weight (0-100) of listener traffic sent to the blue target group - Terraform-driven blue/green shifting, ADR-017"
  type        = number
  default     = 100

  validation {
    condition     = var.blue_weight >= 0 && var.blue_weight <= 100
    error_message = "blue_weight must be between 0 and 100."
  }
}

variable "green_weight" {
  description = "Percentage weight (0-100) of listener traffic sent to the green target group - Terraform-driven blue/green shifting, ADR-017"
  type        = number
  default     = 0

  validation {
    condition     = var.green_weight >= 0 && var.green_weight <= 100
    error_message = "green_weight must be between 0 and 100."
  }

  validation {
    condition     = var.blue_weight + var.green_weight == 100
    error_message = "blue_weight and green_weight must sum to 100, otherwise the listener sends traffic to nowhere or to an unintended split."
  }
}

variable "deregistration_delay_seconds" {
  description = "Seconds the ALB keeps sending an unregistering instance's in-flight requests to it before dropping it - applies to both the blue and green target groups"
  type        = number
  default     = 30

  validation {
    condition     = var.deregistration_delay_seconds >= 0 && var.deregistration_delay_seconds <= 3600
    error_message = "deregistration_delay_seconds must be between 0 and 3600 seconds (the ALB maximum)."
  }
}

variable "health_check_interval_seconds" {
  description = "Seconds between health checks of each target - applies to both the blue and green target groups"
  type        = number
  default     = 10

  validation {
    condition     = var.health_check_interval_seconds >= 5 && var.health_check_interval_seconds <= 300
    error_message = "health_check_interval_seconds must be between 5 and 300 seconds (the ALB limits)."
  }
}

variable "health_check_timeout_seconds" {
  description = "Seconds to wait for a health check response before counting it as failed - applies to both target groups"
  type        = number
  default     = 5

  validation {
    condition     = var.health_check_timeout_seconds >= 2 && var.health_check_timeout_seconds <= 120
    error_message = "health_check_timeout_seconds must be between 2 and 120 seconds (the ALB limits)."
  }

  validation {
    condition     = var.health_check_timeout_seconds < var.health_check_interval_seconds
    error_message = "health_check_timeout_seconds must be smaller than health_check_interval_seconds, otherwise the ALB rejects the target group."
  }
}

variable "health_check_healthy_threshold" {
  description = "Consecutive passing health checks before a target is marked healthy - applies to both target groups"
  type        = number
  default     = 2

  validation {
    condition     = var.health_check_healthy_threshold >= 2 && var.health_check_healthy_threshold <= 10
    error_message = "health_check_healthy_threshold must be between 2 and 10 (the ALB limits)."
  }
}

variable "health_check_unhealthy_threshold" {
  description = "Consecutive failing health checks before a target is marked unhealthy - applies to both target groups"
  type        = number
  default     = 2

  validation {
    condition     = var.health_check_unhealthy_threshold >= 2 && var.health_check_unhealthy_threshold <= 10
    error_message = "health_check_unhealthy_threshold must be between 2 and 10 (the ALB limits)."
  }
}

variable "health_check_matcher" {
  description = "HTTP status codes that count as a passing health check: a code (200), a list (200,204) or a range (200-299) - applies to both target groups"
  type        = string
  default     = "200"

  validation {
    condition     = can(regex("^[0-9]{3}(-[0-9]{3})?(,[0-9]{3}(-[0-9]{3})?)*$", var.health_check_matcher))
    error_message = "health_check_matcher must be HTTP status codes like \"200\", \"200,204\" or \"200-299\"."
  }
}

variable "deletion_protection" {
  description = "ALB deletion protection - on in prod, off in dev. While it is on, neither the console nor terraform destroy can delete the ALB"
  type        = bool
  default     = false
}

variable "alb_log_retention_days" {
  description = "Days ALB access logs are kept in the S3 logs bucket before they expire"
  type        = number
  default     = 90

  validation {
    condition     = var.alb_log_retention_days >= 1 && var.alb_log_retention_days <= 3650
    error_message = "alb_log_retention_days must be between 1 and 3650 days. 0 (never expire) is deliberately not allowed because the bill would grow forever."
  }
}

variable "waf_rate_limit" {
  description = "Requests per 5 minutes a single IP may send through the WAF web ACL on this ALB before it is blocked"
  type        = number
  default     = 2000

  validation {
    condition     = var.waf_rate_limit >= 10 && var.waf_rate_limit <= 2000000000
    error_message = "waf_rate_limit must be between 10 and 2000000000 requests per 5 minutes (the WAF rate-based rule limits)."
  }
}
