provider "aws" {
  region = "eu-west-3"

  default_tags {
    tags = {
      Project     = "cloudforge"
      managedBy   = "terraform"
      Environment = "dev"
    }
  }
}

module "network" {
  source = "../../modules/network"

  environment = "dev"
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_iam_role" "ssm_test_instance" {
  name = "dev-ssm-test-instance"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_test_instance" {
  role       = aws_iam_role.ssm_test_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_test_instance" {
  name = "dev-ssm-test-instance"
  role = aws_iam_role.ssm_test_instance.name
}

resource "aws_security_group" "ssm_test_instance" {
  name_prefix = "dev-ssm-test-instance-"
  description = "No inbound - SSM Session Manager reaches this instance via outbound agent polling only"
  vpc_id      = module.network.vpc_id

  egress {
    description = "HTTPS out to SSM endpoints, via NAT"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "dev-ssm-test-instance-sg"
  }
}

resource "aws_instance" "ssm_test" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = module.network.subnet_ids["app-a"]
  vpc_security_group_ids = [aws_security_group.ssm_test_instance.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_test_instance.name
  ebs_optimized          = true

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name    = "dev-ssm-test-instance"
    Purpose = "M1 evidence - throwaway, safe to destroy"
  }
}
