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
}

variable "instance_type" {
  description = "EC2 instance type for the app ASG"
  type        = string
  default     = "t4g.small"
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

variable "snapshot_identifier" {
  description = "Restore this environment's DB from a snapshot instead of creating an empty one - set by `make <env>-up` after a `make <env>-down` (ADR-015)"
  type        = string
  default     = null
}

variable "alert_email" {
  description = "Email address subscribed to the M7 observability SNS alerts topic"
  type        = string
}

module "network" {
  source = "../../modules/network"

  environment = var.environment
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
  app_port                           = 8080
  images_bucket_id                   = module.storage.images_bucket_id
  images_bucket_arn                  = module.storage.images_bucket_arn
  images_bucket_regional_domain_name = module.storage.images_bucket_regional_domain_name
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
  data_tier_cidr_blocks   = ["10.0.21.0/24", "10.0.22.0/24"]
  db_secret_arn           = module.database.master_user_secret_arn
  instance_type           = var.instance_type
  asg_min_size            = var.asg_min_size
  asg_max_size            = var.asg_max_size
  asg_desired_capacity    = var.asg_desired_capacity
  redis_secret_arn        = module.cache.auth_secret_arn
  redis_tls_server_name   = module.cache.redis_primary_endpoint
}

module "cache" {
  source = "../../modules/cache"

  environment           = var.environment
  vpc_id                = module.network.vpc_id
  data_subnet_ids       = [module.network.subnet_ids["data-a"], module.network.subnet_ids["data-b"]]
  app_security_group_id = module.compute.app_security_group_id
  private_zone_id       = module.network.private_zone_id
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
