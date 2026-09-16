provider "aws" {
  region = "eu-west-3"

  default_tags {
    tags = {
      Project     = "cloudforge"
      managedBy   = "terraform"
      Environment = "dev"
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
      Environment = "dev"
    }
  }
}

variable "snapshot_identifier" {
  description = "Restore dev-cloudforge-db from this snapshot instead of creating an empty one - set by `make dev-up` after a `make dev-down` (ADR-015)"
  type        = string
  default     = null
}

variable "alert_email" {
  description = "Email address subscribed to the M7 observability SNS alerts topic"
  type        = string
}

module "network" {
  source = "../../modules/network"

  environment = "dev"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_iam_role" "ssm_test_instance" {
  name = "dev-ssm-test-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_test_instance" {
  role       = aws_iam_role.ssm_test_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_test_instance" {
  name = "dev-ssm-test-instance"
  role = aws_iam_role.ssm_test_instance.name
}

resource "aws_security_group" "ssm_test_instance" {
  name_prefix = "dev-ssm-test-instance-"
  description = "No inbound - SSM Session Manager reaches this instance via outbound agent polling only"
  vpc_id      = module.network.vpc_id

  egress {
    description = "HTTPS out to SSM endpoints, via NAT"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "dev-ssm-test-instance-sg"
  }
}

resource "aws_instance" "ssm_test" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = module.network.subnet_ids["app-a"]
  vpc_security_group_ids = [aws_security_group.ssm_test_instance.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_test_instance.name
  ebs_optimized          = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name    = "dev-ssm-test-instance"
    Purpose = "M1 evidence - throwaway, safe to destroy"
  }
}

module "storage" {
  source = "../../modules/storage"

  environment = "dev"
}

module "edge" {
  source = "../../modules/edge"

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  environment                        = "dev"
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

  environment             = "dev"
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
  # Deliberately t4g.small, not the module's t4g.micro default: eu-west-3a/3b
  # had no t4g.micro capacity when this was built, and this size has since
  # been proven end-to-end. Kept as the standing choice, not a pending revert.
  instance_type         = "t4g.small"
  redis_secret_arn      = module.cache.auth_secret_arn
  redis_tls_server_name = module.cache.redis_primary_endpoint
}

module "cache" {
  source = "../../modules/cache"

  environment           = "dev"
  vpc_id                = module.network.vpc_id
  data_subnet_ids       = [module.network.subnet_ids["data-a"], module.network.subnet_ids["data-b"]]
  app_security_group_id = module.compute.app_security_group_id
  private_zone_id       = module.network.private_zone_id
}

module "database" {
  source = "../../modules/database"

  environment           = "dev"
  vpc_id                = module.network.vpc_id
  data_subnet_ids       = [module.network.subnet_ids["data-a"], module.network.subnet_ids["data-b"]]
  app_security_group_id = module.compute.app_security_group_id
  private_zone_id       = module.network.private_zone_id
  snapshot_identifier   = var.snapshot_identifier
}

module "observability" {
  source = "../../modules/observability"

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  environment                = "dev"
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
