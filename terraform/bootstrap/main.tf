provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "cloudforge"
      ManagedBy   = "terraform"
      Environment = "bootstrap"
    }
  }
}

resource "random_id" "state_bucket_suffix" {
  byte_length = 4
}

# The 4 checks below are documented and suppressed at the pre-commit-config.yaml
# level (--skip-check), not via inline comments - checkov's inline skip-comment
# syntax doesn't work reliably in this install (an isolated single-resource
# test still failed, and writing out the literal syntax in a comment like this
# one actually crashes checkov's parser - which is why this note avoids it).
# Reasoning for each skipped check:
#
# CKV_AWS_18  (access logging): would need a second bucket just for logs on a
#   bucket only Terraform and you ever touch (already private/public-blocked/TLS-only).
# CKV_AWS_144 (cross-region replication): a DR feature for real data; this bucket
#   only holds Terraform state, recoverable by re-applying the committed config.
# CKV_AWS_145 (SSE-KMS): costs ~$1/mo per key for marginal gain over the AES256
#   encryption already enabled - not worth it on a personal-credits project.
# CKV2_AWS_62 (event notifications): no consumer for bucket events on a state-only bucket.
resource "aws_s3_bucket" "state" {
  bucket = "cloudforge-tfstate-${random_id.state_bucket_suffix.hex}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}


resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.state.arn,
          "${aws_s3_bucket.state.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
