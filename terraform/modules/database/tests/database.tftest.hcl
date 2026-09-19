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

# Plan-only on purpose (ADR-016): an apply-mode RDS test would create a real
# instance, take 10+ minutes, and cost money on every run. Everything asserted
# here is a literal from the configuration, so the plan already knows it.
#
# Not asserted: the security group's ingress rule. AWS's provider marks a
# brand-new security group's ingress/egress as unknown until apply (same
# limitation documented in modules/compute/tests) - verify by reading main.tf.
run "security_baseline" {
  command = plan

  assert {
    condition     = aws_db_instance.main.storage_encrypted == true
    error_message = "RDS storage must be encrypted at rest"
  }

  assert {
    condition     = aws_db_instance.main.publicly_accessible == false
    error_message = "RDS must never be publicly accessible"
  }

  assert {
    condition     = aws_db_instance.main.manage_master_user_password == true
    error_message = "The master password must be AWS-managed in Secrets Manager, never set in config (ADR-009)"
  }

  assert {
    condition     = aws_db_instance.main.iam_database_authentication_enabled == true
    error_message = "IAM database authentication must be enabled"
  }

  assert {
    condition     = aws_db_instance.main.skip_final_snapshot == false
    error_message = "Destroy must take a final snapshot, that is what dev-down/dev-up relies on (ADR-015)"
  }

  assert {
    condition     = length([for p in aws_db_parameter_group.main.parameter : p if p.name == "rds.force_ssl" && p.value == "1" && p.apply_method == "pending-reboot"]) == 1
    error_message = "rds.force_ssl must be 1 and applied as pending-reboot, otherwise unencrypted connections are accepted or the plan shows a perpetual diff"
  }
}

run "dev_profile_is_the_default" {
  command = plan

  assert {
    condition     = aws_db_instance.main.multi_az == false && aws_db_instance.main.deletion_protection == false
    error_message = "Defaults must be the cheap, destroyable dev profile: single-AZ, no deletion protection"
  }

  assert {
    condition     = aws_db_instance.main.backup_retention_period == 1 && aws_db_instance.main.apply_immediately == true
    error_message = "Defaults must be 1 day of backups and apply_immediately = true for fast dev iteration"
  }

  assert {
    condition     = aws_db_instance.main.identifier == "test-cloudforge-db"
    error_message = "Instance identifier must follow <environment>-cloudforge-db"
  }
}

run "prod_profile_flows_through" {
  command = plan

  variables {
    multi_az                = true
    deletion_protection     = true
    backup_retention_period = 7
    apply_immediately       = false
  }

  assert {
    condition     = aws_db_instance.main.multi_az == true && aws_db_instance.main.deletion_protection == true
    error_message = "multi_az and deletion_protection must reach the instance, that is the whole dev-vs-prod difference"
  }

  assert {
    condition     = aws_db_instance.main.backup_retention_period == 7 && aws_db_instance.main.apply_immediately == false
    error_message = "backup_retention_period and apply_immediately must reach the instance"
  }
}

run "dns_record_points_at_the_instance" {
  command = plan

  assert {
    condition     = aws_route53_record.db.name == "db.cloudforge.internal" && aws_route53_record.db.type == "CNAME"
    error_message = "The private DNS name the app connects to must be the db.cloudforge.internal CNAME (ADR-013)"
  }
}

run "wrong_service_instance_class_rejected" {
  command = plan

  variables {
    instance_class = "t4g.micro"
  }

  expect_failures = [var.instance_class]
}

run "storage_below_minimum_rejected" {
  command = plan

  variables {
    allocated_storage = 10
  }

  expect_failures = [var.allocated_storage]
}

run "retention_above_rds_limit_rejected" {
  command = plan

  variables {
    backup_retention_period = 36
  }

  expect_failures = [var.backup_retention_period]
}
