provider "aws" {
  region = "eu-west-3"
}

provider "aws" {
  alias  = "use1"
  region = "us-east-1"
}

variables {
  environment                = "test"
  alert_email                = "alerts@example.com"
  alb_arn_suffix             = "app/test-alb/50dc6c495c0c9188"
  target_group_arn_suffix    = "targetgroup/test-tg/73e2d6bc24d8a067"
  asg_name                   = "test-cloudforge-app"
  app_log_group_name         = "/cloudforge/test/app"
  db_instance_id             = "test-cloudforge-db"
  redis_replication_group_id = "test-cloudforge-redis"
  artifacts_bucket_name      = "test-cloudforge-artifacts"
  artifacts_bucket_arn       = "arn:aws:s3:::test-cloudforge-artifacts"
  cloudfront_domain_name     = "d111111abcdef8.cloudfront.net"
}

run "alarm_thresholds_match_plan" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.alb_unhealthy_hosts.threshold == 1
    error_message = "ALB unhealthy-host alarm must fire at >=1 unhealthy target (PLAN.md M7 table)"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.alb_5xx.threshold == 10 && aws_cloudwatch_metric_alarm.alb_5xx.period == 300
    error_message = "ALB 5xx alarm must fire at >10 in a 5 minute window"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.ec2_cpu.threshold == 80 && aws_cloudwatch_metric_alarm.ec2_cpu.evaluation_periods == 10
    error_message = "EC2 CPU alarm must fire at >80% sustained for 10 minutes"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.redis_evictions.threshold == 0 && aws_cloudwatch_metric_alarm.redis_evictions.comparison_operator == "GreaterThanThreshold"
    error_message = "Any eviction at all must alarm - the cache-aside working set no longer fits"
  }
}

run "composite_alarm_watches_the_right_two_alarms" {
  command = plan

  assert {
    condition     = strcontains(aws_cloudwatch_composite_alarm.service_degraded.alarm_rule, aws_cloudwatch_metric_alarm.alb_unhealthy_hosts.alarm_name)
    error_message = "Composite alarm must reference the unhealthy-hosts alarm"
  }

  assert {
    condition     = strcontains(aws_cloudwatch_composite_alarm.service_degraded.alarm_rule, aws_cloudwatch_metric_alarm.alb_5xx.alarm_name)
    error_message = "Composite alarm must reference the 5xx alarm"
  }
}

run "canary_targets_cloudfront_not_alb" {
  command = plan

  assert {
    condition     = local_file.canary_script.content == templatefile("${path.module}/templates/canary.js.tpl", { target_url = "https://${var.cloudfront_domain_name}/api/products" })
    error_message = "Canary must target the CloudFront domain, not the ALB directly - ADR-014 makes the ALB 403 anything else"
  }

  assert {
    condition     = aws_synthetics_canary.api.schedule[0].expression == "rate(5 minutes)"
    error_message = "Canary must run every 5 minutes per PLAN.md M7"
  }
}

run "sns_subscription_matches_alert_email" {
  command = plan

  assert {
    condition     = aws_sns_topic_subscription.alerts_email.endpoint == var.alert_email
    error_message = "SNS subscription must go to the configured alert email"
  }
}
