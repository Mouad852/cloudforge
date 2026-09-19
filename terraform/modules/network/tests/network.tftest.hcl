provider "aws" {
  region = "eu-west-3"
}

variables {
  environment = "test"
}

run "subnet_count_and_cidrs" {
  command = plan

  assert {
    condition     = length(aws_subnet.this) == 6
    error_message = "Expected exactly 6 subnets (2 Azs x 3 tiers), got ${length(aws_subnet.this)}"
  }

  assert {
    condition     = aws_vpc.main.cidr_block == var.vpc_cidr
    error_message = "VPC CIDR block does not match the vpc_cidr input"
  }

  assert {
    condition = (
      aws_subnet.this["public-a"].cidr_block == "10.0.1.0/24" &&
      aws_subnet.this["public-b"].cidr_block == "10.0.2.0/24" &&
      aws_subnet.this["app-a"].cidr_block == "10.0.11.0/24" &&
      aws_subnet.this["app-b"].cidr_block == "10.0.12.0/24" &&
      aws_subnet.this["data-a"].cidr_block == "10.0.21.0/24" &&
      aws_subnet.this["data-b"].cidr_block == "10.0.22.0/24"
    )
    error_message = "One or more subnet CIDR blocks do not match the intended layout"
  }

  assert {
    condition     = aws_subnet.this["public-a"].map_public_ip_on_launch && aws_subnet.this["public-b"].map_public_ip_on_launch
    error_message = "Public subnets must auto-assign public IPs"
  }

  assert {
    condition = (
      !aws_subnet.this["app-a"].map_public_ip_on_launch &&
      !aws_subnet.this["app-b"].map_public_ip_on_launch &&
      !aws_subnet.this["data-a"].map_public_ip_on_launch &&
      !aws_subnet.this["data-b"].map_public_ip_on_launch
    )
    error_message = "Private subnets (app/data) must not auto-assign public IPs"
  }
}

# The default layout is what dev and prod already run. If deriving the subnets
# from vpc_cidr ever changed these values, Terraform would try to replace live
# subnets, so this pins them.
run "default_data_tier_cidrs_match_the_live_layout" {
  command = plan

  assert {
    condition     = output.data_tier_cidr_blocks == ["10.0.21.0/24", "10.0.22.0/24"]
    error_message = "The default data-tier CIDRs must stay 10.0.21.0/24 and 10.0.22.0/24, the values dev and prod already run"
  }
}

run "subnets_follow_a_different_vpc_cidr" {
  command = plan

  variables {
    vpc_cidr = "172.16.0.0/16"
  }

  assert {
    condition = (
      aws_subnet.this["public-a"].cidr_block == "172.16.1.0/24" &&
      aws_subnet.this["public-b"].cidr_block == "172.16.2.0/24" &&
      aws_subnet.this["app-a"].cidr_block == "172.16.11.0/24" &&
      aws_subnet.this["app-b"].cidr_block == "172.16.12.0/24" &&
      aws_subnet.this["data-a"].cidr_block == "172.16.21.0/24" &&
      aws_subnet.this["data-b"].cidr_block == "172.16.22.0/24"
    )
    error_message = "Subnets must be carved out of vpc_cidr, not hardcoded to 10.0.x.x"
  }

  assert {
    condition     = output.data_tier_cidr_blocks == ["172.16.21.0/24", "172.16.22.0/24"]
    error_message = "data_tier_cidr_blocks must follow vpc_cidr"
  }
}

run "vpc_cidr_with_the_wrong_prefix_rejected" {
  command = plan

  variables {
    vpc_cidr = "10.0.0.0/24"
  }

  expect_failures = [var.vpc_cidr]
}

run "vpc_cidr_that_is_not_a_cidr_rejected" {
  command = plan

  variables {
    vpc_cidr = "not-a-cidr"
  }

  expect_failures = [var.vpc_cidr]
}

run "log_retention_defaults_to_14" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.vpc_flow_logs.retention_in_days == 14
    error_message = "Default log retention must stay 14 days, the value the live environments already run"
  }
}

run "log_retention_flows_through" {
  command = plan

  variables {
    log_retention_days = 30
  }

  assert {
    condition     = aws_cloudwatch_log_group.vpc_flow_logs.retention_in_days == 30
    error_message = "log_retention_days must reach the VPC flow log group"
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

run "private_route_table_never_reaches_igw" {
  command = apply

  assert {
    condition = alltrue([
      for r in aws_route_table.private.route : r.gateway_id != aws_internet_gateway.main.id
    ])
    error_message = "Private route table must never route through the Internet Gateway"
  }

  assert {
    condition = length([
      for r in aws_route_table.public.route :
      r if r.cidr_block == "0.0.0.0/0" && r.gateway_id == aws_internet_gateway.main.id
    ]) == 1
    error_message = "Public route table must send 0.0.0.0/0 to the Internet Gateway"
  }
}
