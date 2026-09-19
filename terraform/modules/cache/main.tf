locals {
  redis_secret_name = "${var.name_prefix}/${var.environment}/redis-auth"
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.environment}-${var.name_prefix}-redis"
  subnet_ids = var.data_subnet_ids

  tags = {
    Name = "${var.environment}-${var.name_prefix}-redis-subnet-group"
  }
}

resource "aws_security_group" "redis" {
  name_prefix = "${var.environment}-${var.name_prefix}-redis-"
  description = "ElastiCache Redis - inbound only from the app security group (M6)"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Redis from app instances only"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }

  tags = {
    Name = "${var.environment}-${var.name_prefix}-redis-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "random_password" "redis_auth" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "redis_auth" {
  name        = local.redis_secret_name
  description = "ElastiCache Redis AUTH token (M6)"
  # dev is destroyed and recreated routinely (nightly-destroy.yml, make
  # dev-down/dev-up) - AWS's default 30-day recovery window blocks every
  # recreate with "already scheduled for deletion" (hit this for real).
  # prod keeps the default recovery window as a safety net.
  recovery_window_in_days = var.environment == "dev" ? 0 : 30
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id = aws_secretsmanager_secret.redis_auth.id
  secret_string = jsonencode({
    auth_token = random_password.redis_auth.result
  })
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${var.environment}-${var.name_prefix}-redis"
  description          = "CloudForge cache-aside Redis (M6)"

  engine         = "redis"
  engine_version = var.engine_version
  node_type      = var.node_type
  port           = 6379

  num_cache_clusters         = 1
  automatic_failover_enabled = false

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = random_password.redis_auth.result

  apply_immediately = var.apply_immediately

  tags = {
    Name = "${var.environment}-${var.name_prefix}-redis"
  }
}

# Optional: a stable private name in front of the AWS-generated endpoint, so
# app config never embeds the generated hostname (ADR-013).
resource "aws_route53_record" "cache" {
  count = var.dns_record_name == null ? 0 : 1

  zone_id = var.private_zone_id
  name    = var.dns_record_name
  type    = "CNAME"
  ttl     = var.dns_ttl_seconds
  records = [aws_elasticache_replication_group.main.primary_endpoint_address]
}

# The record used to be unconditional. Without this, adding count would make
# Terraform destroy the live record and create a new one at cache[0].
moved {
  from = aws_route53_record.cache
  to   = aws_route53_record.cache[0]
}
