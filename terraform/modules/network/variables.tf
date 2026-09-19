variable "environment" {
  description = "Environment name (dev, prod, or test), used in resource naming/tags"
  type        = string

  validation {
    condition     = contains(["dev", "prod", "test"], var.environment)
    error_message = "environment must be one of: dev, prod, test."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC - must be a /16, the module carves six /24 subnets out of it"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && can(regex("/16$", var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block with a /16 prefix, for example 10.0.0.0/16."
  }
}

variable "nat_instance_type" {
  description = "Instance type for the NAT instance"
  type        = string
  default     = "t3.micro"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention, in days, for the VPC flow log group"
  type        = number
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a retention period CloudWatch Logs supports (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 or 3653). 0 (never expire) is deliberately not allowed because the bill would grow forever."
  }
}
