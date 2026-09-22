provider "aws" {
  region = "eu-west-3"
}

variables {
  environment       = "test"
  vpc_id            = "vpc-0123456789abcdef0"
  vpc_cidr          = "10.0.0.0/16"
  public_subnet_ids = ["subnet-aaaaaaaaaaaaaaaaa", "subnet-bbbbbbbbbbbbbbbbb"]
}

# aws_security_group's ingress/egress blocks are marked unknown at plan time
# regardless of literal config (same limitation documented in
# modules/compute/tests) - not asserted here, verify by reading main.tf.
# ADR-025: the ALB security group's ingress is 0.0.0.0/0 on port 80 by
# design now that there is no CloudFront in front of it.
run "target_groups_and_listener" {
  command = plan

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
    condition     = aws_lb_listener.http.default_action[0].type == "forward"
    error_message = "ADR-025: with no CloudFront to gate on, the listener's default action must forward directly - there is nothing left to deny by default"
  }

  # The forward block's target_group set (count, ARNs, weights) is unknown
  # at plan time, the same limitation the SG note above already documents -
  # not asserted here, verify the two-target-group weighted forward by
  # reading main.tf.
}

run "waf_associated_directly_with_the_alb" {
  command = plan

  assert {
    condition     = aws_wafv2_web_acl.alb.scope == "REGIONAL"
    error_message = "ADR-025: the web ACL must be REGIONAL scope, associated directly with the ALB - there is no CloudFront distribution to attach a CLOUDFRONT-scope ACL to"
  }

  # Both ARNs in the association are computed values, unknown at plan time
  # (same limitation noted above) - that this module has exactly one
  # aws_wafv2_web_acl_association, pointed at its own web ACL, is verified
  # by reading main.tf.
}

run "deregistration_delay_defaults_to_30_on_both_target_groups" {
  command = plan

  assert {
    condition     = tonumber(aws_lb_target_group.blue.deregistration_delay) == 30 && tonumber(aws_lb_target_group.green.deregistration_delay) == 30
    error_message = "Default deregistration delay must stay 30s on both target groups, the value the live environments already run"
  }
}

run "deregistration_delay_flows_through_to_both_target_groups" {
  command = plan

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

  variables {
    deregistration_delay_seconds = 3601
  }

  expect_failures = [var.deregistration_delay_seconds]
}

run "negative_deregistration_delay_rejected" {
  command = plan

  variables {
    deregistration_delay_seconds = -1
  }

  expect_failures = [var.deregistration_delay_seconds]
}

run "health_check_defaults_match_the_live_environments" {
  command = plan

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

  variables {
    health_check_interval_seconds = 4
  }

  expect_failures = [var.health_check_interval_seconds]
}

run "health_check_interval_above_the_alb_maximum_rejected" {
  command = plan

  variables {
    health_check_interval_seconds = 301
  }

  expect_failures = [var.health_check_interval_seconds]
}

run "health_check_timeout_equal_to_the_interval_rejected" {
  command = plan

  variables {
    health_check_interval_seconds = 10
    health_check_timeout_seconds  = 10
  }

  expect_failures = [var.health_check_timeout_seconds]
}

run "health_check_timeout_below_the_alb_minimum_rejected" {
  command = plan

  variables {
    health_check_timeout_seconds = 1
  }

  expect_failures = [var.health_check_timeout_seconds]
}

run "health_check_thresholds_outside_2_to_10_rejected" {
  command = plan

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

  variables {
    health_check_matcher = "ok"
  }

  expect_failures = [var.health_check_matcher]
}

run "alb_deletion_protection_defaults_to_off" {
  command = plan

  assert {
    condition     = aws_lb.app.enable_deletion_protection == false
    error_message = "Deletion protection must default to off, the value dev already runs"
  }
}

run "alb_deletion_protection_flows_through" {
  command = plan

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

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.alb_logs.rule).expiration[0].days == 90
    error_message = "Default ALB log retention must stay 90 days, the value the live environments already run"
  }
}

run "alb_log_retention_flows_through" {
  command = plan

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

  variables {
    alb_log_retention_days = 0
  }

  expect_failures = [var.alb_log_retention_days]
}

run "alb_log_retention_over_ten_years_rejected" {
  command = plan

  variables {
    alb_log_retention_days = 3651
  }

  expect_failures = [var.alb_log_retention_days]
}

run "waf_rate_limit_defaults_to_2000" {
  command = plan

  assert {
    condition     = one([for r in aws_wafv2_web_acl.alb.rule : r if r.name == "RateLimitPerIP"]).statement[0].rate_based_statement[0].limit == 2000
    error_message = "Default WAF rate limit must stay 2000 requests per 5 minutes, the value the live environments already run"
  }
}

run "waf_rate_limit_flows_through" {
  command = plan

  variables {
    waf_rate_limit = 500
  }

  assert {
    condition     = one([for r in aws_wafv2_web_acl.alb.rule : r if r.name == "RateLimitPerIP"]).statement[0].rate_based_statement[0].limit == 500
    error_message = "waf_rate_limit must reach the rate-based rule"
  }
}

run "waf_rate_limit_below_the_waf_minimum_rejected" {
  command = plan

  variables {
    waf_rate_limit = 9
  }

  expect_failures = [var.waf_rate_limit]
}

run "waf_rate_limit_above_the_waf_maximum_rejected" {
  command = plan

  variables {
    waf_rate_limit = 2000000001
  }

  expect_failures = [var.waf_rate_limit]
}
