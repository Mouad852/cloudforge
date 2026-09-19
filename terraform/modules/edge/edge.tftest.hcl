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
