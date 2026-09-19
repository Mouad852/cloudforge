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

variable "origin_secret_header_name" {
  description = "Header name CloudFront injects and the ALB listener checks for - the real authorization boundary, ADR-014"
  type        = string
  default     = "X-Origin-Verify"
}

variable "images_bucket_id" {
  description = "S3 images bucket name (modules/storage) - the OAC bucket policy target, M6"
  type        = string
}

variable "images_bucket_arn" {
  description = "S3 images bucket ARN (modules/storage) - used in the OAC bucket policy, M6"
  type        = string
}

variable "images_bucket_regional_domain_name" {
  description = "S3 images bucket regional domain name (modules/storage) - CloudFront's /images/* origin, M6"
  type        = string
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
