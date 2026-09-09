variable "environment" {
  description = "Environment name (dev or prod), used in resource naming/tags"
  type        = string
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
