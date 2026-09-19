provider "aws" {
  region = "eu-west-3"
}

variables {
  environment           = "test"
  vpc_id                = "vpc-0123456789abcdef0"
  data_subnet_ids       = ["subnet-ccccccccccccccccc", "subnet-ddddddddddddddddd"]
  app_security_group_id = "sg-0123456789abcdef0"
  private_zone_id       = "Z0123456789ABCDEFGHIJ"
}

run "encryption_and_auth" {
  command = plan

  override_resource {
    target          = random_password.redis_auth
    override_during = plan
    values = {
      result = "not-a-real-secret-fixture-value"
    }
  }

  assert {
    condition     = tostring(aws_elasticache_replication_group.main.at_rest_encryption_enabled) == "true"
    error_message = "Redis must encrypt data at rest"
  }

  assert {
    condition     = tostring(aws_elasticache_replication_group.main.transit_encryption_enabled) == "true"
    error_message = "Redis must encrypt data in transit"
  }

  assert {
    condition     = aws_elasticache_replication_group.main.auth_token == "not-a-real-secret-fixture-value"
    error_message = "Redis must be configured with the generated AUTH token"
  }

  assert {
    condition     = tostring(aws_elasticache_replication_group.main.automatic_failover_enabled) == "false"
    error_message = "Single-node dev cache must not attempt automatic failover"
  }

  assert {
    condition     = aws_secretsmanager_secret.redis_auth.name == "cloudforge/test/redis-auth"
    error_message = "Redis AUTH secret name must match modules/compute's IAM policy naming convention"
  }
}

run "dns_ttl_defaults_to_300" {
  command = plan

  assert {
    condition     = aws_route53_record.cache.ttl == 300
    error_message = "Default DNS TTL must stay 300s, the value the live environments already run"
  }
}

run "dns_ttl_flows_through" {
  command = plan

  variables {
    dns_ttl_seconds = 60
  }

  assert {
    condition     = aws_route53_record.cache.ttl == 60
    error_message = "dns_ttl_seconds must reach the cache DNS record"
  }
}

run "dns_ttl_over_a_day_rejected" {
  command = plan

  variables {
    dns_ttl_seconds = 86401
  }

  expect_failures = [var.dns_ttl_seconds]
}

run "negative_dns_ttl_rejected" {
  command = plan

  variables {
    dns_ttl_seconds = -1
  }

  expect_failures = [var.dns_ttl_seconds]
}
