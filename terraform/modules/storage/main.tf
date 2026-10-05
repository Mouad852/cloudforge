# Only the artifacts bucket lived here until M6. M3's compute layer needs
# somewhere to pull the app binary from (ADR-004) before it can boot at all,
# so it couldn't wait. The "logs" bucket this module's repo-structure comment
# once anticipated turned out to already be covered by modules/edge's
# alb_logs bucket (M4) - no separate one is added here. Images (below) reuses
# this same bucket_suffix, as originally planned.

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "artifacts" {
  bucket = "cloudforge-artifacts-${var.environment}-${random_id.bucket_suffix.hex}"

  # prod-down is intentionally a full teardown. The app binary and canary
  # output are reproducible; planned recovery is limited to the RDS snapshot.
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    id     = "expire-old-artifact-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.artifact_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_days
    }
  }

  # The Synthetics canary (modules/observability) writes a report under
  # canary/<env>/ on every run. Those are current versions, so the rule above
  # never touched them and they piled up forever (found in M10). Expiring them
  # leaves a delete marker; the old version then goes a day later, not after
  # the 90 days kept for superseded app binaries. Where two rules overlap, S3
  # acts on whichever expires the object first.
  rule {
    id     = "expire-canary-reports"
    status = "Enabled"

    filter {
      prefix = "canary/"
    }

    expiration {
      days = var.canary_report_retention_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }

  depends_on = [aws_s3_bucket_versioning.artifacts]
}


resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.artifacts.arn,
        "${aws_s3_bucket.artifacts.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}

resource "aws_s3_bucket" "images" {
  bucket = "cloudforge-images-${var.environment}-${random_id.bucket_suffix.hex}"

  # Product images are deliberately outside the RDS recovery boundary.
  # See docs/disaster-recovery/strategy.md.
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "images" {
  bucket = aws_s3_bucket.images.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket = aws_s3_bucket.images.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ADR-025: this used to live in modules/edge, which needed the CloudFront
# distribution's ARN for an OAC-allow statement. With no CloudFront, the app
# is the only reader/writer (via its own IAM role, granted since M3) - this
# bucket needs nothing beyond the same TLS-only deny every other bucket in
# this project already has.
resource "aws_s3_bucket_policy" "images" {
  bucket = aws_s3_bucket.images.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.images.arn,
        "${aws_s3_bucket.images.arn}/*",
      ]
      Condition = {
        Bool = { "aws:SecureTransport" = "false" }
      }
    }]
  })
}
