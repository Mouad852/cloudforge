provider "aws" {
  region = "eu-west-3"

  default_tags {
    tags = {
      Project     = "cloudforge"
      managedBy   = "terraform"
      Environment = var.environment
    }
  }
}

provider "aws" {
  alias  = "use1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "cloudforge"
      managedBy   = "terraform"
      Environment = var.environment
    }
  }
}

variable "environment" {
  description = "Environment name (dev, prod, or test)"
  type        = string

  validation {
    condition     = contains(["dev", "prod", "test"], var.environment)
    error_message = "environment must be one of: dev, prod, test."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the app ASG"
  type        = string
  default     = "t4g.small"
}

variable "app_port" {
  description = "Port the app listens on - the ALB (edge) targets it and the app security group and service (compute) use it"
  type        = number
  default     = 8080

  validation {
    condition     = var.app_port >= 1 && var.app_port <= 65535
    error_message = "app_port must be a valid TCP port between 1 and 65535."
  }
}

variable "asg_min_size" {
  description = "ASG minimum size"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "ASG maximum size"
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "ASG desired capacity"
  type        = number
  default     = 1
}

variable "green_asg_min_size" {
  description = "Green ASG minimum size - 0 by default so the idle blue/green fleet costs nothing outside a deploy window (ADR-017)"
  type        = number
  default     = 0
}

variable "green_asg_max_size" {
  description = "Green ASG maximum size - matches blue's ceiling so green can take over blue's full traffic during a cutover"
  type        = number
  default     = 6
}

variable "green_asg_desired_capacity" {
  description = "Green ASG desired capacity - 0 outside a deploy window, scaled up before shifting traffic to green"
  type        = number
  default     = 0
}

variable "blue_weight" {
  description = "Percentage (0-100) of ALB traffic sent to the blue fleet - shifted with green_weight during a blue/green deploy (ADR-017)"
  type        = number
  default     = 100

  validation {
    condition     = var.blue_weight >= 0 && var.blue_weight <= 100
    error_message = "blue_weight must be between 0 and 100."
  }
}

variable "green_weight" {
  description = "Percentage (0-100) of ALB traffic sent to the green fleet - shifted with blue_weight during a blue/green deploy (ADR-017)"
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

variable "db_multi_az" {
  description = "RDS Multi-AZ deployment - on in prod, off in dev"
  type        = bool
  default     = false
}

variable "db_deletion_protection" {
  description = "RDS deletion protection - on in prod, off in dev"
  type        = bool
  default     = false
}

variable "db_backup_retention_period" {
  description = "RDS automated backup retention in days"
  type        = number
  default     = 1
}

variable "db_apply_immediately" {
  description = "Apply RDS modifications immediately instead of waiting for the next maintenance window - on in dev for fast iteration, off in prod to avoid mid-day disruption"
  type        = bool
  default     = true
}

variable "db_instance_class" {
  description = "RDS instance class - sized per environment through tfvars"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB - sized per environment through tfvars"
  type        = number
  default     = 20
}

variable "cache_node_type" {
  description = "ElastiCache node type - sized per environment through tfvars"
  type        = string
  default     = "cache.t4g.micro"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention, in days, for the app and VPC flow log groups"
  type        = number
  default     = 14
}

variable "alb_deletion_protection" {
  description = "ALB deletion protection - on in prod, off in dev"
  type        = bool
  default     = false
}

variable "alb_log_retention_days" {
  description = "Days ALB access logs are kept in S3 before they expire"
  type        = number
  default     = 90
}

variable "snapshot_identifier" {
  description = "Restore this environment's DB from a snapshot instead of creating an empty one - set by `make <env>-up` after a `make <env>-down` (ADR-015)"
  type        = string
  default     = null
}

variable "alert_email" {
  description = "Email address subscribed to the M7 observability SNS alerts topic"
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email))
    error_message = "alert_email must look like an email address (name@domain.tld). A typo here means the SNS subscription is never confirmed and no alarm ever reaches anyone."
  }
}

module "network" {
  source = "../../modules/network"

  environment        = var.environment
  log_retention_days = var.log_retention_days
}

module "storage" {
  source = "../../modules/storage"

  environment = var.environment
}

module "edge" {
  source = "../../modules/edge"

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  environment                        = var.environment
  vpc_id                             = module.network.vpc_id
  vpc_cidr                           = module.network.vpc_cidr
  public_subnet_ids                  = [module.network.subnet_ids["public-a"], module.network.subnet_ids["public-b"]]
  app_port                           = var.app_port
  blue_weight                        = var.blue_weight
  green_weight                       = var.green_weight
  images_bucket_id                   = module.storage.images_bucket_id
  images_bucket_arn                  = module.storage.images_bucket_arn
  images_bucket_regional_domain_name = module.storage.images_bucket_regional_domain_name
  deletion_protection                = var.alb_deletion_protection
  alb_log_retention_days             = var.alb_log_retention_days
}

module "compute" {
  source = "../../modules/compute"

  environment             = var.environment
  vpc_id                  = module.network.vpc_id
  app_subnet_ids          = [module.network.subnet_ids["app-a"], module.network.subnet_ids["app-b"]]
  artifacts_bucket_arn    = module.storage.artifacts_bucket_arn
  artifacts_bucket_name   = module.storage.artifacts_bucket_name
  images_bucket_name      = module.storage.images_bucket_id
  alb_security_group_id   = module.edge.alb_security_group_id
  target_group_arns       = [module.edge.blue_target_group_arn]
  green_target_group_arns = [module.edge.green_target_group_arn]
  data_tier_cidr_blocks   = module.network.data_tier_cidr_blocks
  db_secret_arn           = module.database.master_user_secret_arn
  instance_type           = var.instance_type
  app_port                = var.app_port
  asg_min_size            = var.asg_min_size
  asg_max_size            = var.asg_max_size
  asg_desired_capacity    = var.asg_desired_capacity
  log_retention_days      = var.log_retention_days
  redis_addr              = "${module.cache.dns_name}:${module.cache.redis_port}"
  redis_secret_arn        = module.cache.auth_secret_arn
  redis_tls_server_name   = module.cache.redis_primary_endpoint

  green_asg_min_size         = var.green_asg_min_size
  green_asg_max_size         = var.green_asg_max_size
  green_asg_desired_capacity = var.green_asg_desired_capacity
}

module "cache" {
  source = "../../modules/cache"

  environment           = var.environment
  vpc_id                = module.network.vpc_id
  data_subnet_ids       = [module.network.subnet_ids["data-a"], module.network.subnet_ids["data-b"]]
  app_security_group_id = module.compute.app_security_group_id
  private_zone_id       = module.network.private_zone_id
  dns_record_name       = "cache.cloudforge.internal"
  node_type             = var.cache_node_type
}

module "database" {
  source = "../../modules/database"

  environment             = var.environment
  vpc_id                  = module.network.vpc_id
  data_subnet_ids         = [module.network.subnet_ids["data-a"], module.network.subnet_ids["data-b"]]
  app_security_group_id   = module.compute.app_security_group_id
  private_zone_id         = module.network.private_zone_id
  snapshot_identifier     = var.snapshot_identifier
  multi_az                = var.db_multi_az
  deletion_protection     = var.db_deletion_protection
  backup_retention_period = var.db_backup_retention_period
  apply_immediately       = var.db_apply_immediately
  instance_class          = var.db_instance_class
  allocated_storage       = var.db_allocated_storage
}

module "observability" {
  source = "../../modules/observability"

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  environment                = var.environment
  alert_email                = var.alert_email
  alb_arn_suffix             = module.edge.alb_arn_suffix
  target_group_arn_suffix    = module.edge.blue_target_group_arn_suffix
  asg_name                   = module.compute.asg_name
  app_log_group_name         = module.compute.app_log_group_name
  db_instance_id             = module.database.instance_id
  redis_replication_group_id = module.cache.replication_group_id
  artifacts_bucket_name      = module.storage.artifacts_bucket_name
  artifacts_bucket_arn       = module.storage.artifacts_bucket_arn
  cloudfront_domain_name     = module.edge.cloudfront_domain_name
}
