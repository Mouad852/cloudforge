# The NAT instance's AMI comes from a most_recent data source, so a new AL2023
# release changes it on some later plan. Replacing the instance drops all
# private-subnet egress, so main.tf sets ignore_changes = [ami].
#
# This needs two applies with different AMIs, which is why it runs against a
# mocked provider: nothing real is created, and it needs no AWS credentials.
mock_provider "aws" {
  # The mock validates ARN-typed arguments, so give it real-looking ARNs.
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:eu-west-3:123456789012:log-group:/test/vpc-flow-logs"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/test-role"
    }
  }
}

variables {
  environment = "test"
}

# The mock returns an empty list, but the module slices the first two Azs.
override_data {
  target = data.aws_availability_zones.available
  values = {
    names = ["eu-west-3a", "eu-west-3b", "eu-west-3c"]
  }
}

run "nat_instance_launches_with_the_current_ami" {
  command = apply

  override_data {
    target = data.aws_ami.al2023
    values = {
      id = "ami-0aaaaaaaaaaaaaaaa"
    }
  }

  assert {
    condition     = aws_instance.nat.ami == "ami-0aaaaaaaaaaaaaaaa"
    error_message = "The NAT instance should launch from the AMI the data source returned"
  }
}

run "a_newer_ami_does_not_replace_the_nat_instance" {
  command = apply

  override_data {
    target = data.aws_ami.al2023
    values = {
      id = "ami-0bbbbbbbbbbbbbbbb"
    }
  }

  assert {
    condition     = aws_instance.nat.ami == "ami-0aaaaaaaaaaaaaaaa"
    error_message = "A newer AMI must not change (and so replace) the running NAT instance - ignore_changes = [ami] is missing"
  }
}
