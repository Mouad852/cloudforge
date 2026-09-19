variable "environment" {
  description = "Environment name (dev, prod, or test), used in resource naming/tags"
  type        = string

  validation {
    condition     = contains(["dev", "prod", "test"], var.environment)
    error_message = "environment must be one of: dev, prod, test."
  }
}

variable "vpc_id" {
  description = "VPC ID the compute layer runs in"
  type        = string
}

variable "artifacts_bucket_arn" {
  description = "ARN of the S3 bucket the app binary is pulled from (modules/storage)"
  type        = string
}

variable "images_bucket_name" {
  description = "Name of the M6 images bucket. Not created yet - the IAM role is pre-scoped to this name so M6 needs no policy changes, only rewiring this variable to the real bucket once it exists."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (Graviton/arm64, ADR-003)"
  type        = string
  default     = "t4g.micro"

  validation {
    condition     = can(regex("^[a-z]+[0-9]+g[a-z]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be a Graviton (arm64) type such as t4g.small - the AMI is arm64-only, so an x86 type would only fail at instance launch (ADR-003)."
  }
}

variable "artifacts_bucket_name" {
  description = "Name of the S3 bucket the app binary is pulled from (modules/storage)"
  type        = string
}

variable "artifact_key" {
  description = "S3 key of the app binary within the artifacts bucket"
  type        = string
  default     = "cloudstore-api/cloudstore-api"
}

variable "app_port" {
  description = "Port the app listens on"
  type        = number
  default     = 8080
}

variable "app_subnet_ids" {
  description = "App-tier subnet IDs (both Azs) the ASG launches into"
  type        = list(string)
}

variable "asg_min_size" {
  description = "ASG minimum size"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "ASG maximum size"
  type        = number
  default     = 6

  validation {
    condition     = var.asg_max_size >= var.asg_min_size
    error_message = "asg_max_size must be greater than or equal to asg_min_size."
  }
}

variable "asg_desired_capacity" {
  description = "ASG desired capacity"
  type        = number
  default     = 2

  validation {
    condition     = var.asg_desired_capacity >= var.asg_min_size && var.asg_desired_capacity <= var.asg_max_size
    error_message = "asg_desired_capacity must be between asg_min_size and asg_max_size."
  }
}

variable "target_group_arns" {
  description = "ALB target group ARNs to attach the ASG to - M4 wires this in; empty until then"
  type        = list(string)
  default     = []
}


variable "alb_security_group_id" {
  description = "ALB's security group ID (modules/edge) - the app SG allows inbound only from this, M4"
  type        = string
}

variable "data_tier_cidr_blocks" {
  description = "Data-tier subnet CIDRs - the app SG's egress for RDS/Redis is scoped to these, not the whole VPC"
  type        = list(string)
}

variable "db_secret_arn" {
  description = "Secrets Manager ARN for the RDS master password (ADR-009) - empty string means no database configured yet"
  type        = string
  default     = ""
}

variable "redis_addr" {
  description = "Redis host:port app instances connect to (M6)"
  type        = string
  default     = "cache.cloudforge.internal:6379"
}

variable "redis_secret_arn" {
  description = "Secrets Manager ARN for the Redis AUTH token (M6) - empty string means no cache configured yet"
  type        = string
  default     = ""
}

variable "redis_tls_server_name" {
  description = "Real ElastiCache hostname for TLS certificate verification (M6) - differs from redis_addr, which is our own Route 53 CNAME (ADR-013); empty string means no cache configured yet"
  type        = string
  default     = ""
}

variable "green_asg_min_size" {
  description = "Green ASG minimum size - 0 by default so the idle blue/green fleet costs nothing outside a deploy window"
  type        = number
  default     = 0
}

variable "green_asg_max_size" {
  description = "Green ASG maximum size - matches blue's ceiling so it can take over blue's full traffic during a cutover"
  type        = number
  default     = 6

  validation {
    condition     = var.green_asg_max_size >= var.green_asg_min_size
    error_message = "green_asg_max_size must be greater than or equal to green_asg_min_size."
  }
}

variable "green_asg_desired_capacity" {
  description = "Green ASG desired capacity - 0 by default, scaled up only during a blue/green deploy"
  type        = number
  default     = 0

  validation {
    condition     = var.green_asg_desired_capacity >= var.green_asg_min_size && var.green_asg_desired_capacity <= var.green_asg_max_size
    error_message = "green_asg_desired_capacity must be between green_asg_min_size and green_asg_max_size."
  }
}

variable "green_target_group_arns" {
  description = "ALB green target group ARNs to attach the green ASG to"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention, in days, for the app log group"
  type        = number
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a retention period CloudWatch Logs supports (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288 or 3653). 0 (never expire) is deliberately not allowed because the bill would grow forever."
  }
}
