terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "cloudforge-tfstate-f1909561"
    key          = "dev/terraform.tfstate"
    region       = "eu-west-3"
    use_lockfile = true
  }
}
