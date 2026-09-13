provider "aws" {
  region = "eu-west-3"
}

variables {
  environment = "test"
}

run "bucket_naming_and_lockdown" {
  command = plan

  override_resource {
    target          = random_id.bucket_suffix
    override_during = plan
    values = {
      hex = "00000000"
    }
  }

  assert {
    condition     = startswith(aws_s3_bucket.artifacts.bucket, "cloudforge-artifacts-test-")
    error_message = "Artifacts bucket name must follow the cloudforge-artifacts-<environment>-<suffix> convention"
  }

  assert {
    condition     = aws_s3_bucket_versioning.artifacts.versioning_configuration[0].status == "Enabled"
    error_message = "Artifacts bucket must be versioned"
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.artifacts.block_public_acls &&
      aws_s3_bucket_public_access_block.artifacts.block_public_policy &&
      aws_s3_bucket_public_access_block.artifacts.ignore_public_acls &&
      aws_s3_bucket_public_access_block.artifacts.restrict_public_buckets
    )
    error_message = "Artifacts bucket must block all public access"
  }
}
