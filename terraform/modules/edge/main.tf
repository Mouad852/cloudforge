data "aws_elb_service_account" "main" {}

resource "random_id" "alb_logs_bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "alb_logs" {
  bucket = "cloudforge-alb-logs-${var.environment}-${random_id.alb_logs_bucket_suffix.hex}"
  # dev is meant to be fully destroyable (ADR-012/ADR-015) - without this,
  # a populated, versioned bucket blocks terraform destroy outright.
  force_destroy = var.environment == "dev"
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

# ADR-025: CloudFront access was permanently denied, so this ALB is the
# public edge itself - there is nothing left to narrow inbound traffic to.
# The old rule scoped ingress to CloudFront's origin-facing prefix list
# (ADR-014); that lockdown has nothing to lock the ALB behind any more.
resource "aws_security_group" "alb" {
  name_prefix = "${var.environment}-cloudforge-alb-"
  description = "ALB - the public edge (ADR-025, no CloudFront in front of it); HTTP open to the internet by design"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from the internet - this ALB is the public edge, protected by the WAF web ACL below (ADR-025)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

  enable_deletion_protection = var.deletion_protection
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

  deregistration_delay = var.deregistration_delay_seconds

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = var.health_check_matcher
    interval            = var.health_check_interval_seconds
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    timeout             = var.health_check_timeout_seconds
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

  deregistration_delay = var.deregistration_delay_seconds

  health_check {
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = var.health_check_matcher
    interval            = var.health_check_interval_seconds
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    timeout             = var.health_check_timeout_seconds
  }

  tags = {
    Name = "${var.environment}-cloudforge-green-tg"
  }
}

# ADR-025: no CloudFront in front of this ALB, so there is nothing to gate
# the default action on any more - the old default was a fixed 403, and only
# a listener rule matching a CloudFront-injected secret header could forward
# (ADR-014). The weighted blue/green forward (ADR-017) is now the default
# action directly.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.blue.arn
        weight = var.blue_weight
      }

      target_group {
        arn    = aws_lb_target_group.green.arn
        weight = var.green_weight
      }

      stickiness {
        enabled  = false
        duration = 1
      }
    }
  }

  tags = {
    Name = "${var.environment}-cloudforge-alb-listener"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "expire-old-access-logs"
    status = "Enabled"

    filter {}

    expiration {
      days = var.alb_log_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ADR-025: REGIONAL scope, associated directly with the ALB below - there is
# no CloudFront distribution to attach a CLOUDFRONT-scope web ACL to any
# more. A REGIONAL web ACL lives in the same region as the resource it
# protects, so this needs no aws.use1 provider, unlike the old one.
resource "aws_wafv2_web_acl" "alb" {
  name  = "${var.environment}-cloudforge-alb-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 0

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # Count, not block: the rule below re-applies this 8 KB body limit
        # everywhere except the image upload, which the app caps at 5 MiB.
        rule_action_override {
          name = "SizeRestrictions_BODY"

          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  # Must run after CommonRuleSet (priority 0), which adds the label it matches.
  rule {
    name     = "OversizedBodyExceptImageUpload"
    priority = 5

    action {
      block {}
    }

    statement {
      and_statement {
        statement {
          label_match_statement {
            scope = "LABEL"
            key   = "awswaf:managed:aws:core-rule-set:SizeRestrictions_Body"
          }
        }

        statement {
          not_statement {
            statement {
              regex_match_statement {
                regex_string = "^/api/products/[^/]+/image$"

                field_to_match {
                  uri_path {}
                }

                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-oversized-body"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # Requests per IP per 5 minutes (var.waf_rate_limit). The 2000 default is
  # generous enough not to trip during normal demo traffic or a load test,
  # low enough to catch an obvious script kiddie.
  rule {
    name     = "RateLimitPerIP"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # CommonRuleSet has no SQL-injection rules; this group is what catches them.
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 4

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.environment}-sqli"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.environment}-cloudforge-alb-waf"
    sampled_requests_enabled   = true
  }

  tags = {
    Name = "${var.environment}-cloudforge-alb-waf"
  }
}

resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.app.arn
  web_acl_arn  = aws_wafv2_web_acl.alb.arn
}
