# Account-wide settings added in M10 (Well-Architected review): EBS encryption
# by default, cost allocation tags, and the M0 console CloudTrail brought under
# Terraform. Like the state bucket and Access Analyzer, none of this belongs to
# one environment.

# CloudTrail's home Region and the Cost Explorer API are both us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "cloudforge"
      ManagedBy   = "terraform"
      Environment = "bootstrap"
      Owner       = "Mouad852"
    }
  }
}

data "aws_caller_identity" "current" {}

# encryption-inventory G9: every new EBS volume in eu-west-3 is encrypted with
# the account's default key (alias/aws/ebs), including one created by hand or by
# a module that forgets `encrypted = true`. Free, and it only affects volumes
# created after it is turned on.
resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

# Until a tag is activated here, Cost Explorer and the billing reports cannot
# group or filter by it. These are the four tags every stack sets through
# default_tags (enforced by CKV_CF_1). Grouping starts from the day of
# activation; earlier costs stay untagged.
resource "aws_ce_cost_allocation_tag" "this" {
  for_each = toset(["Project", "Environment", "Owner", "ManagedBy"])
  provider = aws.us_east_1

  tag_key = each.key
  status  = "Active"
}

# The trail and its bucket were created in the console in M0. Importing them
# puts their settings in code (encryption-inventory G5, data-classification D2).
# The bucket itself stays unmanaged: only its policy and lifecycle are set here.
locals {
  account_id        = data.aws_caller_identity.current.account_id
  cloudtrail_name   = "management-events"
  cloudtrail_arn    = "arn:aws:cloudtrail:us-east-1:${local.account_id}:trail/${local.cloudtrail_name}"
  cloudtrail_bucket = "aws-cloudtrail-logs-${local.account_id}-ba75d0e4"
}

import {
  to = aws_cloudtrail.management_events
  id = local.cloudtrail_arn
}

import {
  to = aws_s3_bucket_policy.cloudtrail
  id = local.cloudtrail_bucket
}

# Same trail as M0: all Regions, global service events, management events only.
# New: log file validation, so CloudTrail signs an hourly digest of the files it
# wrote and `aws cloudtrail validate-logs` can prove none was changed or deleted.
resource "aws_cloudtrail" "management_events" {
  provider = aws.us_east_1

  name                          = local.cloudtrail_name
  s3_bucket_name                = local.cloudtrail_bucket
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  advanced_event_selector {
    name = "Management events selector"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

# The two statements the console wrote so CloudTrail can deliver, plus the
# TLS-only deny every other bucket in the project already has.
resource "aws_s3_bucket_policy" "cloudtrail" {
  provider = aws.us_east_1

  bucket = local.cloudtrail_bucket

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = "arn:aws:s3:::${local.cloudtrail_bucket}"
        Condition = {
          StringEquals = { "AWS:SourceArn" = local.cloudtrail_arn }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "arn:aws:s3:::${local.cloudtrail_bucket}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "AWS:SourceArn" = local.cloudtrail_arn
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "arn:aws:s3:::${local.cloudtrail_bucket}",
          "arn:aws:s3:::${local.cloudtrail_bucket}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
    ]
  })
}

# CloudTrail records who called what and from which IP (Confidential in
# data-classification.md), so it gets a retention instead of living forever.
# One year: long enough to investigate an incident noticed late. CloudTrail's
# own event history already keeps the last 90 days for free.
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  provider = aws.us_east_1

  bucket = local.cloudtrail_bucket

  rule {
    id     = "expire-after-one-year"
    status = "Enabled"

    filter {}

    expiration {
      days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
