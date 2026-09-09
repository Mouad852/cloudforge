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
