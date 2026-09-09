provider "aws" {
  region = "eu-west-3"
}

variables {
  environment           = "test"
  vpc_id                 = "vpc-0123456789abcdef0"
  artifacts_bucket_arn   = "arn:aws:s3:::cloudforge-artifacts-test-00000000"
  artifacts_bucket_name  = "cloudforge-artifacts-test-00000000"
  images_bucket_name     = "cloudforge-images-test"
  app_subnet_ids         = ["subnet-aaaaaaaaaaaaaaaaa", "subnet-bbbbbbbbbbbbbbbbb"]
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
    condition     = tonumber(aws_autoscaling_group.app.instance_refresh[0].preferences[0].instance_warmup) == 180
    error_message = "Instance refresh warmup must be 180s - got ${aws_autoscaling_group.app.instance_refresh[0].preferences[0].instance_warmup}"
  }



  assert {
    condition     = aws_autoscaling_lifecycle_hook.terminating.lifecycle_transition == "autoscaling:EC2_INSTANCE_TERMINATING"
    error_message = "Lifecycle hook must fire on instance termination"
  }
}
