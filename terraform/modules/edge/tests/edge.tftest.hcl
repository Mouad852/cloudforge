provider "aws" {
  region = "eu-west-3"
}

provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}

variables {
  environment                        = "test"
  vpc_id                             = "vpc-0123456789abcdef0"
  vpc_cidr                           = "10.0.0.0/16"
  public_subnet_ids                  = ["subnet-aaaaaaaaaaaaaaaaa", "subnet-bbbbbbbbbbbbbbbbb"]
  images_bucket_id                   = "cloudforge-images-test-00000000"
  images_bucket_arn                  = "arn:aws:s3:::cloudforge-images-test-00000000"
  images_bucket_regional_domain_name = "cloudforge-images-test-00000000.s3.eu-west-3.amazonaws.com"
}

# aws_security_group's ingress/egress blocks are marked unknown at plan time
# regardless of literal config (same limitation documented in
# modules/compute/tests) - not asserted here, verify by reading main.tf.
run "target_groups_and_listener" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  assert {
    condition     = aws_lb_target_group.blue.health_check[0].path == "/healthz" && aws_lb_target_group.green.health_check[0].path == "/healthz"
    error_message = "Both target groups must use the shallow /healthz check"
  }

  assert {
    condition     = aws_lb_target_group.blue.health_check[0].interval == 10 && aws_lb_target_group.blue.health_check[0].healthy_threshold == 2 && aws_lb_target_group.blue.health_check[0].unhealthy_threshold == 2
    error_message = "Health check must be 10s interval, 2/2 thresholds"
  }

  assert {
    condition     = tonumber(aws_lb_target_group.blue.deregistration_delay) == 30
    error_message = "Deregistration delay must be 30s"
  }

  assert {
    condition     = aws_lb_listener.http.default_action[0].type == "fixed-response" && aws_lb_listener.http.default_action[0].fixed_response[0].status_code == "403"
    error_message = "Listener must deny by default (403) - only the header-matched rule may forward"
  }

  assert {
    condition = anytrue(flatten([
      for c in aws_lb_listener_rule.from_cloudfront.condition : [
        for h in c.http_header : h.http_header_name == var.origin_secret_header_name
      ]
    ]))
    error_message = "Listener rule must gate on the shared secret header"
  }
}

run "cloudfront_images_behavior" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  override_resource {
    target          = aws_cloudfront_origin_access_control.images
    override_during = plan
    values = {
      id = "E1TESTOACIDXXXXX"
    }
  }

  assert {
    condition     = aws_cloudfront_origin_access_control.images.signing_behavior == "always"
    error_message = "Images OAC must always sign requests to S3"
  }

  assert {
    condition = anytrue([
      for b in aws_cloudfront_distribution.app.ordered_cache_behavior :
      b.path_pattern == "/images/*" && b.target_origin_id == "images-s3"
    ])
    error_message = "Distribution must route /images/* to the images-s3 origin"
  }

  assert {
    condition = anytrue([
      for o in aws_cloudfront_distribution.app.origin :
      o.origin_id == "images-s3" && o.origin_access_control_id == "E1TESTOACIDXXXXX"
    ])
    error_message = "The images-s3 origin must use the OAC, not a public bucket"
  }
}

run "deregistration_delay_defaults_to_30_on_both_target_groups" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  assert {
    condition     = tonumber(aws_lb_target_group.blue.deregistration_delay) == 30 && tonumber(aws_lb_target_group.green.deregistration_delay) == 30
    error_message = "Default deregistration delay must stay 30s on both target groups, the value the live environments already run"
  }
}

run "deregistration_delay_flows_through_to_both_target_groups" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    deregistration_delay_seconds = 120
  }

  assert {
    condition     = tonumber(aws_lb_target_group.blue.deregistration_delay) == 120 && tonumber(aws_lb_target_group.green.deregistration_delay) == 120
    error_message = "deregistration_delay_seconds must reach both the blue and green target groups"
  }
}

run "deregistration_delay_over_the_alb_maximum_rejected" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    deregistration_delay_seconds = 3601
  }

  expect_failures = [var.deregistration_delay_seconds]
}

run "negative_deregistration_delay_rejected" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    deregistration_delay_seconds = -1
  }

  expect_failures = [var.deregistration_delay_seconds]
}

run "health_check_defaults_match_the_live_environments" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  assert {
    condition = alltrue([
      for tg in [aws_lb_target_group.blue, aws_lb_target_group.green] :
      tg.health_check[0].matcher == "200" && tg.health_check[0].interval == 10 && tg.health_check[0].timeout == 5 && tg.health_check[0].healthy_threshold == 2 && tg.health_check[0].unhealthy_threshold == 2
    ])
    error_message = "Default health check must stay 200 / 10s interval / 5s timeout / 2 healthy / 2 unhealthy on both target groups, the values the live environments already run"
  }
}

run "health_check_settings_flow_through_to_both_target_groups" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    health_check_interval_seconds    = 30
    health_check_timeout_seconds     = 10
    health_check_healthy_threshold   = 3
    health_check_unhealthy_threshold = 4
    health_check_matcher             = "200-299"
  }

  assert {
    condition = alltrue([
      for tg in [aws_lb_target_group.blue, aws_lb_target_group.green] :
      tg.health_check[0].matcher == "200-299" && tg.health_check[0].interval == 30 && tg.health_check[0].timeout == 10 && tg.health_check[0].healthy_threshold == 3 && tg.health_check[0].unhealthy_threshold == 4
    ])
    error_message = "The health check variables must reach both the blue and green target groups"
  }
}

run "health_check_interval_below_the_alb_minimum_rejected" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    health_check_interval_seconds = 4
  }

  expect_failures = [var.health_check_interval_seconds]
}

run "health_check_interval_above_the_alb_maximum_rejected" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    health_check_interval_seconds = 301
  }

  expect_failures = [var.health_check_interval_seconds]
}

run "health_check_timeout_equal_to_the_interval_rejected" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    health_check_interval_seconds = 10
    health_check_timeout_seconds  = 10
  }

  expect_failures = [var.health_check_timeout_seconds]
}

run "health_check_timeout_below_the_alb_minimum_rejected" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    health_check_timeout_seconds = 1
  }

  expect_failures = [var.health_check_timeout_seconds]
}

run "health_check_thresholds_outside_2_to_10_rejected" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    health_check_healthy_threshold   = 1
    health_check_unhealthy_threshold = 11
  }

  expect_failures = [
    var.health_check_healthy_threshold,
    var.health_check_unhealthy_threshold,
  ]
}

run "health_check_matcher_that_is_not_status_codes_rejected" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    health_check_matcher = "ok"
  }

  expect_failures = [var.health_check_matcher]
}

run "alb_deletion_protection_defaults_to_off" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  assert {
    condition     = aws_lb.app.enable_deletion_protection == false
    error_message = "Deletion protection must default to off, the value dev already runs"
  }
}

run "alb_deletion_protection_flows_through" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    deletion_protection = true
  }

  assert {
    condition     = aws_lb.app.enable_deletion_protection == true
    error_message = "deletion_protection must reach the ALB"
  }
}

run "alb_log_retention_defaults_to_90_days" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.alb_logs.rule).expiration[0].days == 90
    error_message = "Default ALB log retention must stay 90 days, the value the live environments already run"
  }
}

run "alb_log_retention_flows_through" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    alb_log_retention_days = 14
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.alb_logs.rule).expiration[0].days == 14
    error_message = "alb_log_retention_days must reach the log bucket's expiration rule"
  }
}

run "alb_log_retention_of_zero_rejected" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    alb_log_retention_days = 0
  }

  expect_failures = [var.alb_log_retention_days]
}

run "alb_log_retention_over_ten_years_rejected" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    alb_log_retention_days = 3651
  }

  expect_failures = [var.alb_log_retention_days]
}

run "waf_rate_limit_defaults_to_2000" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  assert {
    condition     = one([for r in aws_wafv2_web_acl.cloudfront.rule : r if r.name == "RateLimitPerIP"]).statement[0].rate_based_statement[0].limit == 2000
    error_message = "Default WAF rate limit must stay 2000 requests per 5 minutes, the value the live environments already run"
  }
}

run "waf_rate_limit_flows_through" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    waf_rate_limit = 500
  }

  assert {
    condition     = one([for r in aws_wafv2_web_acl.cloudfront.rule : r if r.name == "RateLimitPerIP"]).statement[0].rate_based_statement[0].limit == 500
    error_message = "waf_rate_limit must reach the rate-based rule"
  }
}

run "waf_rate_limit_below_the_waf_minimum_rejected" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    waf_rate_limit = 9
  }

  expect_failures = [var.waf_rate_limit]
}

run "waf_rate_limit_above_the_waf_maximum_rejected" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    waf_rate_limit = 2000000001
  }

  expect_failures = [var.waf_rate_limit]
}

run "price_class_defaults_to_100" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  assert {
    condition     = aws_cloudfront_distribution.app.price_class == "PriceClass_100"
    error_message = "Default price class must stay PriceClass_100, the value the live environments already run"
  }
}

run "price_class_flows_through" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    price_class = "PriceClass_All"
  }

  assert {
    condition     = aws_cloudfront_distribution.app.price_class == "PriceClass_All"
    error_message = "price_class must reach the distribution"
  }
}

run "unknown_price_class_rejected" {
  command = plan

  providers = {
    aws      = aws
    aws.use1 = aws.use1
  }

  variables {
    price_class = "PriceClass_Everything"
  }

  expect_failures = [var.price_class]
}
