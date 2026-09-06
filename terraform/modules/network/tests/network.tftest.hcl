provider "aws" {
  region = "eu-west-3"
}

variables {
    environment = "test"
}

run "subnet_count_and_cidrs" {
    command = plan

    assert {
        condition = length(aws_subnet.this) == 6
        error_message = "Expected exactly 6 subnets (2 Azs x 3 tiers), got ${length(aws_subnet.this)}"
    }

    assert {
        condition = aws_vpc.main.cidr_block == var.vpc_cidr
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
        condition = aws_subnet.this["public-a"].map_public_ip_on_launch && aws_subnet.this["public-b"].map_public_ip_on_launch
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
