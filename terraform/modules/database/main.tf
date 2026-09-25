resource "aws_db_subnet_group" "main" {
  name       = "${var.environment}-cloudforge-db"
  subnet_ids = var.data_subnet_ids

  tags = {
    Name = "${var.environment}-cloudforge-db-subnet-group"
  }
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.environment}-cloudforge-rds-"
  description = "PostgreSQL - inbound only from the app security group (M5)"
  vpc_id      = var.vpc_id

  ingress {
    description     = "PostgreSQL from app instances only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }

  tags = {
    Name = "${var.environment}-cloudforge-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "main" {
  name_prefix = "${var.environment}-cloudforge-pg16-"
  family      = "postgres16"
  description = "Slow-query and connection logging to CloudWatch (M5)"

  parameter {
    name  = "log_min_duration_statement"
    value = "500"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  # rds.force_ssl is a "static" RDS parameter - AWS always applies it as
  # pending-reboot regardless of what's requested, so declaring it any
  # other way here just creates a perpetual diff against real state.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = "${var.environment}-cloudforge-pg16"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Unique per apply, so a "dev-down" (final snapshot taken on destroy) never
# collides with a leftover snapshot name from a previous round trip.
resource "random_id" "final_snapshot_suffix" {
  byte_length = 4
}

resource "aws_db_instance" "main" {
  identifier     = "${var.environment}-cloudforge-db"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage = var.allocated_storage
  storage_encrypted = true

  db_name                     = var.db_name
  username                    = var.master_username
  manage_master_user_password = true
  # Restoring from a snapshot ignores db_name/username above (RDS inherits
  # them from the snapshot itself) - null means create fresh (ADR-015).
  snapshot_identifier = var.snapshot_identifier

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.main.name

  publicly_accessible = false
  apply_immediately   = var.apply_immediately

  multi_az            = var.multi_az
  deletion_protection = var.deletion_protection

  backup_retention_period             = var.backup_retention_period
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${var.environment}-cloudforge-db-final-${random_id.final_snapshot_suffix.hex}"
  copy_tags_to_snapshot               = true
  auto_minor_version_upgrade          = true
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  tags = {
    Name = "${var.environment}-cloudforge-db"
  }

  # snapshot_identifier only matters when the instance is created. Changing it
  # afterwards forces a replacement, which would swap a running database for a
  # new one restored from that snapshot. Ignoring it means a restore only ever
  # happens on a fresh create (dev-up, ADR-015), never on a routine apply.
  lifecycle {
    ignore_changes = [snapshot_identifier]
  }
}

resource "aws_route53_record" "db" {
  zone_id = var.private_zone_id
  name    = "db.cloudforge.internal"
  type    = "CNAME"
  ttl     = var.dns_ttl_seconds
  records = [aws_db_instance.main.address]
}
