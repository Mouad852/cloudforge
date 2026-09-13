data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  # Ours to choose - M6 creates the actual secret under this name.
  redis_secret_name_prefix = "cloudforge/${var.environment}/redis-auth"
  log_group_name           = "/cloudforge/${var.environment}/app"
}

resource "aws_iam_role" "app" {
  name = "${var.environment}-cloudforge-app"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.environment}-cloudforge-app"
  role = aws_iam_role.app.name
}

resource "aws_cloudwatch_log_group" "app" {
  name              = local.log_group_name
  retention_in_days = 14
}

resource "aws_iam_role_policy" "app" {
  name = "${var.environment}-cloudforge-app-least-privilege"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadArtifacts"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${var.artifacts_bucket_arn}/*"
      },
      {
        Sid    = "ReadWriteImages"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "arn:aws:s3:::${var.images_bucket_name}/*"
      },
      {
        Sid    = "ReadAppSecrets"
        Effect = "Allow"
        Action = "secretsmanager:GetSecretValue"
        Resource = [
          # RDS's own auto-generated master-password secret (manage_master_user_password,
          # M5). AWS names these "rds!db-<id>" - never chosen by us - so this is scoped
          # to the fixed prefix AWS itself always uses, not a blanket wildcard.
          "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:rds!*",
          # Redis AUTH token secret (M6) - the name is ours to pick; committing to the
          # convention now means this policy needs no changes once M6 creates it.
          "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${local.redis_secret_name_prefix}-*",
        ]
      },
      {
        # cloudwatch:PutMetricData has no ARN format - AWS's IAM reference lists it as
        # one of the handful of actions that only support Resource: "*". The namespace
        # condition is the real scoping mechanism: this role can only ever publish into
        # our own metrics namespace, never anyone else's.
        Sid      = "PutCustomMetrics"
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "CloudForge/EC2"
          }
        }
      },
      {
        Sid    = "AppLogGroup"
        Effect = "Allow"
        Action = "logs:*"
        Resource = [
          aws_cloudwatch_log_group.app.arn,
          "${aws_cloudwatch_log_group.app.arn}:*",
        ]
      },
    ]
  })
}

resource "aws_security_group" "app" {
  name_prefix = "${var.environment}-cloudforge-app-"
  description = "CloudStore API instances - inbound only from the ALB (M4)"
  vpc_id      = var.vpc_id

  ingress {
    description     = "From the ALB only"
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }

  egress {
    description = "HTTPS out for SSM, CloudWatch, Secrets Manager, S3 (via gateway endpoint), via NAT"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "PostgreSQL to the data tier only (M5) - Redis (M7) adds 6379 the same way"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.data_tier_cidr_blocks
  }

  tags = {
    Name = "${var.environment}-cloudforge-app-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

data "aws_ami" "al2023_arm64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "${var.environment}-cloudforge-app-"
  image_id      = data.aws_ami.al2023_arm64.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.app.id]
  }

  metadata_options {
    http_tokens   = "required" # IMDSv2 required - mitigates SSRF credential theft
    http_endpoint = "enabled"
  }

  block_device_mappings {
    device_name = data.aws_ami.al2023_arm64.root_device_name

    ebs {
      encrypted   = true
      volume_size = 30
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tpl", {
    artifacts_bucket = var.artifacts_bucket_name
    artifact_key     = var.artifact_key
    aws_region       = data.aws_region.current.name
    app_port         = var.app_port
    log_group_name   = local.log_group_name
    db_secret_arn    = var.db_secret_arn
  }))

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.environment}-cloudforge-app"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "app" {
  name = "${var.environment}-cloudforge-app"

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  vpc_zone_identifier = var.app_subnet_ids
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity

  health_check_type         = "ELB" # M4 attaches the target group; until then this behaves like EC2 checks
  health_check_grace_period = 300
  target_group_arns         = var.target_group_arns

  instance_refresh {
    strategy = "Rolling"
    triggers = ["launch_template"]

    preferences {
      min_healthy_percentage = 100
      instance_warmup        = 180
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.environment}-cloudforge-app"
    propagate_at_launch = true
  }

}

# Delays actual instance termination so the app's own graceful-shutdown drain
# (app/config.go's DrainTimeout) and the future ALB deregistration delay (M4)
# have room to finish before the instance is really stopped. No completion
# handler (Lambda/EventBridge) - default_result=CONTINUE means ASG proceeds
# once heartbeat_timeout elapses regardless, so a stuck drain can never wedge
# the ASG indefinitely.
resource "aws_autoscaling_lifecycle_hook" "terminating" {
  name                   = "${var.environment}-drain-on-terminate"
  autoscaling_group_name = aws_autoscaling_group.app.name
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
  default_result         = "CONTINUE"
  heartbeat_timeout      = 90
}

# ADR-007's ALBRequestCountPerTarget half is added once M4's target group
# exists - can't reference a resource_label for a target group that isn't
# built yet.
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${var.environment}-cloudforge-app-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 60.0
  }
}
