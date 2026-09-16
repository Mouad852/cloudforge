variable "environment" {
  description = "Environment name (dev or prod), used in resource naming/tags"
  type        = string
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
}

variable "asg_desired_capacity" {
  description = "ASG desired capacity"
  type        = number
  default     = 2
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
}

variable "green_asg_desired_capacity" {
  description = "Green ASG desired capacity - 0 by default, scaled up only during a blue/green deploy"
  type        = number
  default     = 0
}

variable "green_target_group_arns" {
  description = "ALB green target group ARNs to attach the green ASG to"
  type        = list(string)
  default     = []
}
