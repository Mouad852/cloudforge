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

run "images_bucket_naming_and_lockdown" {
  command = plan

  override_resource {
    target          = random_id.bucket_suffix
    override_during = plan
    values = {
      hex = "00000000"
    }
  }

  assert {
    condition     = startswith(aws_s3_bucket.images.bucket, "cloudforge-images-test-")
    error_message = "Images bucket name must follow the cloudforge-images-<environment>-<suffix> convention"
  }

  assert {
    condition     = aws_s3_bucket_versioning.images.versioning_configuration[0].status == "Enabled"
    error_message = "Images bucket must be versioned"
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.images.block_public_acls &&
      aws_s3_bucket_public_access_block.images.block_public_policy &&
      aws_s3_bucket_public_access_block.images.ignore_public_acls &&
      aws_s3_bucket_public_access_block.images.restrict_public_buckets
    )
    error_message = "Images bucket must block all public access"
  }
}

run "artifact_lifecycle_defaults_match_the_live_environments" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.artifacts.rule).noncurrent_version_expiration[0].noncurrent_days == 90
    error_message = "Default noncurrent artifact version retention must stay 90 days, the value the live environments already run"
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.artifacts.rule).abort_incomplete_multipart_upload[0].days_after_initiation == 7
    error_message = "Default multipart abort window must stay 7 days, the value the live environments already run"
  }
}

run "artifact_lifecycle_settings_flow_through" {
  command = plan

  variables {
    artifact_version_retention_days = 30
    abort_incomplete_multipart_days = 2
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.artifacts.rule).noncurrent_version_expiration[0].noncurrent_days == 30
    error_message = "artifact_version_retention_days must reach the noncurrent version expiration rule"
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.artifacts.rule).abort_incomplete_multipart_upload[0].days_after_initiation == 2
    error_message = "abort_incomplete_multipart_days must reach the multipart abort rule"
  }
}

run "artifact_version_retention_of_zero_rejected" {
  command = plan

  variables {
    artifact_version_retention_days = 0
  }

  expect_failures = [var.artifact_version_retention_days]
}

run "artifact_version_retention_over_ten_years_rejected" {
  command = plan

  variables {
    artifact_version_retention_days = 3651
  }

  expect_failures = [var.artifact_version_retention_days]
}

run "multipart_abort_window_of_zero_rejected" {
  command = plan

  variables {
    abort_incomplete_multipart_days = 0
  }

  expect_failures = [var.abort_incomplete_multipart_days]
}

run "multipart_abort_window_over_a_year_rejected" {
  command = plan

  variables {
    abort_incomplete_multipart_days = 366
  }

  expect_failures = [var.abort_incomplete_multipart_days]
}
