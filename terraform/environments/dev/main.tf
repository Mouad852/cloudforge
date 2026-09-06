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
