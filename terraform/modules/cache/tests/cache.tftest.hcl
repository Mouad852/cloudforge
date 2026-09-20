provider "aws" {
  region = "eu-west-3"
}

variables {
  environment           = "test"
  vpc_id                = "vpc-0123456789abcdef0"
  data_subnet_ids       = ["subnet-ccccccccccccccccc", "subnet-ddddddddddddddddd"]
  app_security_group_id = "sg-0123456789abcdef0"
  private_zone_id       = "Z0123456789ABCDEFGHIJ"
  dns_record_name       = "cache.cloudforge.internal"
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
    condition     = aws_route53_record.cache[0].ttl == 300
    error_message = "Default DNS TTL must stay 300s, the value the live environments already run"
  }
}

run "dns_ttl_flows_through" {
  command = plan

  variables {
    dns_ttl_seconds = 60
  }

  assert {
    condition     = aws_route53_record.cache[0].ttl == 60
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

# The default prefix is what dev and prod already run. Renaming any of these
# would replace the live Redis, its subnet group and its security group.
run "default_names_match_the_live_environments" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.main.replication_group_id == "test-cloudforge-redis"
    error_message = "Default replication group ID must stay <env>-cloudforge-redis"
  }

  assert {
    condition     = aws_elasticache_subnet_group.main.name == "test-cloudforge-redis"
    error_message = "Default subnet group name must stay <env>-cloudforge-redis"
  }

  assert {
    condition     = aws_security_group.redis.name_prefix == "test-cloudforge-redis-"
    error_message = "Default security group name prefix must stay <env>-cloudforge-redis-"
  }
}

run "name_prefix_flows_through_every_name" {
  command = plan

  variables {
    name_prefix = "acme"
  }

  assert {
    condition     = aws_elasticache_replication_group.main.replication_group_id == "test-acme-redis"
    error_message = "name_prefix must reach the replication group ID"
  }

  assert {
    condition     = aws_elasticache_subnet_group.main.name == "test-acme-redis" && aws_security_group.redis.name_prefix == "test-acme-redis-"
    error_message = "name_prefix must reach the subnet group and security group names"
  }

  assert {
    condition     = aws_secretsmanager_secret.redis_auth.name == "acme/test/redis-auth"
    error_message = "name_prefix must reach the Secrets Manager path"
  }
}

run "uppercase_name_prefix_rejected" {
  command = plan

  variables {
    name_prefix = "Acme"
  }

  expect_failures = [var.name_prefix]
}

run "name_prefix_ending_in_a_hyphen_rejected" {
  command = plan

  variables {
    name_prefix = "acme-"
  }

  expect_failures = [var.name_prefix]
}

run "name_prefix_with_a_double_hyphen_rejected" {
  command = plan

  variables {
    name_prefix = "acme--corp"
  }

  expect_failures = [var.name_prefix]
}

run "name_prefix_too_long_for_a_replication_group_id_rejected" {
  command = plan

  variables {
    name_prefix = "abcdefghijklmnopqrstuvwxyzabc"
  }

  expect_failures = [var.name_prefix]
}

run "dns_record_is_named_by_the_variable" {
  command = plan

  variables {
    dns_record_name = "cache.example.internal"
  }

  assert {
    condition     = aws_route53_record.cache[0].name == "cache.example.internal" && aws_route53_record.cache[0].type == "CNAME"
    error_message = "The CNAME must be named by dns_record_name"
  }

  assert {
    condition     = output.dns_name == "cache.example.internal"
    error_message = "The dns_name output must return the record name"
  }
}

run "no_dns_record_when_no_name_is_given" {
  command = plan

  variables {
    dns_record_name = null
    private_zone_id = null
  }

  assert {
    condition     = length(aws_route53_record.cache) == 0
    error_message = "With no dns_record_name the module must not create a DNS record"
  }

  assert {
    condition     = output.dns_name == null
    error_message = "dns_name must be null when there is no record"
  }
}

run "dns_record_name_without_a_zone_rejected" {
  command = plan

  variables {
    dns_record_name = "cache.example.internal"
    private_zone_id = null
  }

  expect_failures = [var.dns_record_name]
}

run "dns_record_name_that_is_not_a_fqdn_rejected" {
  command = plan

  variables {
    dns_record_name = "cache"
  }

  expect_failures = [var.dns_record_name]
}

run "uppercase_dns_record_name_rejected" {
  command = plan

  variables {
    dns_record_name = "Cache.Example.Internal"
  }

  expect_failures = [var.dns_record_name]
}
