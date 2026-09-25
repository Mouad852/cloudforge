provider "aws" {
  region = "eu-west-3"
}
variables {
  environment           = "test"
  vpc_id                = "vpc-0123456789abcdef0"
  artifacts_bucket_arn  = "arn:aws:s3:::cloudforge-artifacts-test-00000000"
  artifacts_bucket_name = "cloudforge-artifacts-test-00000000"
  images_bucket_name    = "cloudforge-images-test"
  app_subnet_ids        = ["subnet-aaaaaaaaaaaaaaaaa", "subnet-bbbbbbbbbbbbbbbbb"]
  alb_security_group_id = "sg-0123456789abcdef0"
  data_tier_cidr_blocks = ["10.0.21.0/24", "10.0.22.0/24"]
}

# The security group's "no ingress yet" claim isn't covered here: AWS's
# provider marks a brand-new security group's ingress/egress as unknown
# until apply, and proving it via a real apply would need a throwaway VPC
# just for this one check. It's a 2-attribute resource with no ingress
# block written at all - verify by reading main.tf directly.
run "iam_least_privilege" {
  command = plan

  override_resource {
    target          = aws_cloudwatch_log_group.app
    override_during = plan
    values = {
      arn = "arn:aws:logs:eu-west-3:123456789012:log-group:/cloudforge/test/app"
    }
  }

  assert {
    condition = alltrue([
      for s in jsondecode(aws_iam_role_policy.app.policy).Statement :
      s.Resource != "*" || can(s.Condition)
    ])
    error_message = "Every statement with Resource = \"*\" must carry a Condition (only cloudwatch:PutMetricData qualifies - it has no ARN format in IAM)"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.ssm.policy_arn == "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    error_message = "App role must have AmazonSSMManagedInstanceCore attached for SSM access"
  }
}


run "asg_and_scaling_config" {
  command = plan

  assert {
    condition     = aws_autoscaling_group.app.min_size == 2 && aws_autoscaling_group.app.max_size == 6 && aws_autoscaling_group.app.desired_capacity == 2
    error_message = "ASG must be min=2 desired=2 max=6"
  }

  assert {
    condition     = aws_autoscaling_group.app.health_check_type == "ELB" && aws_autoscaling_group.app.health_check_grace_period == 300
    error_message = "ASG must use ELB health checks with a 300s grace period"
  }

  assert {
    condition     = aws_autoscaling_group.app.instance_refresh[0].preferences[0].min_healthy_percentage == 100
    error_message = "Instance refresh must keep 100% healthy - got ${aws_autoscaling_group.app.instance_refresh[0].preferences[0].min_healthy_percentage}"
  }

  assert {
    condition     = aws_autoscaling_group.app.instance_refresh[0].preferences[0].max_healthy_percentage == 200
    error_message = "Instance refresh must launch the replacement before terminating the old instance (max_healthy_percentage 200) - got ${aws_autoscaling_group.app.instance_refresh[0].preferences[0].max_healthy_percentage}"
  }

  assert {
    condition     = tonumber(aws_autoscaling_group.app.instance_refresh[0].preferences[0].instance_warmup) == 180
    error_message = "Instance refresh warmup must be 180s - got ${aws_autoscaling_group.app.instance_refresh[0].preferences[0].instance_warmup}"
  }



  assert {
    condition     = aws_autoscaling_lifecycle_hook.terminating.lifecycle_transition == "autoscaling:EC2_INSTANCE_TERMINATING"
    error_message = "Lifecycle hook must fire on instance termination"
  }
}

run "user_data_uses_unix_line_endings" {
  command = plan

  assert {
    condition     = !strcontains(base64decode(aws_launch_template.app.user_data), "\r")
    error_message = "The rendered user_data contains CRLF line endings, so bash on the instance would fail at the shebang. Check .gitattributes covers *.tpl and re-checkout the template."
  }
}

run "log_retention_defaults_to_14" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.app.retention_in_days == 14
    error_message = "Default log retention must stay 14 days, the value the live environments already run"
  }
}

run "log_retention_flows_through" {
  command = plan

  variables {
    log_retention_days = 30
  }

  assert {
    condition     = aws_cloudwatch_log_group.app.retention_in_days == 30
    error_message = "log_retention_days must reach the app log group"
  }
}

run "log_retention_unsupported_value_rejected" {
  command = plan

  variables {
    log_retention_days = 10
  }

  expect_failures = [var.log_retention_days]
}

run "log_retention_never_expire_rejected" {
  command = plan

  variables {
    log_retention_days = 0
  }

  expect_failures = [var.log_retention_days]
}

# The defaults are what dev and prod already run. Changing one would roll the
# launch template or the scaling policy on live environments.
run "tunable_defaults_match_the_live_values" {
  command = plan

  assert {
    condition     = aws_launch_template.app.block_device_mappings[0].ebs[0].volume_size == 30
    error_message = "Default root volume must stay 30 GiB, the value the live environments already run"
  }

  assert {
    condition     = aws_autoscaling_group.app.health_check_grace_period == 300 && aws_autoscaling_group.app_green.health_check_grace_period == 300
    error_message = "Default grace period must stay 300s on both the blue and green ASGs"
  }

  assert {
    condition     = aws_autoscaling_policy.cpu_target_tracking.target_tracking_configuration[0].target_value == 60
    error_message = "Default CPU target must stay 60%"
  }
}

run "tunables_flow_through" {
  command = plan

  variables {
    root_volume_size_gb       = 50
    health_check_grace_period = 120
    cpu_target_percent        = 45
  }

  assert {
    condition     = aws_launch_template.app.block_device_mappings[0].ebs[0].volume_size == 50
    error_message = "root_volume_size_gb must reach the launch template"
  }

  assert {
    condition     = aws_autoscaling_group.app.health_check_grace_period == 120 && aws_autoscaling_group.app_green.health_check_grace_period == 120
    error_message = "health_check_grace_period must reach both the blue and green ASGs"
  }

  assert {
    condition     = aws_autoscaling_policy.cpu_target_tracking.target_tracking_configuration[0].target_value == 45
    error_message = "cpu_target_percent must reach the target-tracking policy"
  }
}

run "root_volume_smaller_than_the_ami_snapshot_rejected" {
  command = plan

  variables {
    root_volume_size_gb = 4
  }

  expect_failures = [var.root_volume_size_gb]
}

run "negative_grace_period_rejected" {
  command = plan

  variables {
    health_check_grace_period = -1
  }

  expect_failures = [var.health_check_grace_period]
}

run "grace_period_over_an_hour_rejected" {
  command = plan

  variables {
    health_check_grace_period = 7200
  }

  expect_failures = [var.health_check_grace_period]
}

run "cpu_target_of_zero_rejected" {
  command = plan

  variables {
    cpu_target_percent = 0
  }

  expect_failures = [var.cpu_target_percent]
}

run "cpu_target_above_100_rejected" {
  command = plan

  variables {
    cpu_target_percent = 101
  }

  expect_failures = [var.cpu_target_percent]
}
