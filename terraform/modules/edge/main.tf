data "aws_elb_service_account" "main" {}

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# Shared secret CloudFront (Step 2) injects as a custom origin header and the
# ALB listener checks for. The prefix-list SG rule below only proves a
# request came from CloudFront's edge network in general - that range is
# shared by every CloudFront distribution on AWS, including someone else's
# pointed at this ALB's DNS name as a custom origin. This header is the
# actual authorization boundary (ADR-014).
resource "random_password" "origin_secret" {
  length  = 32
  special = false
}

resource "random_id" "alb_logs_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "alb_logs" {
  bucket = "cloudforge-alb-logs-${var.environment}-${random_id.alb_logs_bucket_suffix.hex}"
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowALBLogDelivery"
      Effect    = "Allow"
      Principal = { AWS = data.aws_elb_service_account.main.arn }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.alb_logs.arn}/alb/*"
    }]
  })
}

resource "aws_security_group" "alb" {
  name_prefix = "${var.environment}-cloudforge-alb-"
  description = "ALB - inbound restricted to CloudFront's own IP range, never 0.0.0.0/0"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from CloudFront origin-facing IP range only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    description = "To app instances only, on the app port"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "${var.environment}-cloudforge-alb-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb" "app" {
  name               = "${var.environment}-cloudforge-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = false
  drop_invalid_header_fields = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.id
    prefix  = "alb"
    enabled = true
  }

  tags = {
    Name = "${var.environment}-cloudforge-alb"
  }

  depends_on = [aws_s3_bucket_policy.alb_logs]
}

resource "aws_lb_target_group" "blue" {
  name        = "${var.environment}-cloudforge-blue"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }

  tags = {
    Name = "${var.environment}-cloudforge-blue-tg"
  }
}

resource "aws_lb_target_group" "green" {
  name        = "${var.environment}-cloudforge-green"
  port        = var.app_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }

  tags = {
    Name = "${var.environment}-cloudforge-green-tg"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  # Deny by default. Only the rule below, matched on the shared secret
  # header, may forward anywhere.
  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Forbidden"
      status_code  = "403"
    }
  }

  tags = {
    Name = "${var.environment}-cloudforge-alb-listener"
  }
}

resource "aws_lb_listener_rule" "from_cloudfront" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  condition {
    http_header {
      http_header_name = var.origin_secret_header_name
      values           = [random_password.origin_secret.result]
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-old-access-logs"
    status = "Enabled"

    expiration {
      days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
