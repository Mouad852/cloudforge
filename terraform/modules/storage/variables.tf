variable "environment" {
  description = "Environment name (dev, prod, or test), used in resource naming/tags"
  type        = string

  validation {
    condition     = contains(["dev", "prod", "test"], var.environment)
    error_message = "environment must be one of: dev, prod, test."
  }
}

variable "artifact_version_retention_days" {
  description = "Days a superseded (noncurrent) version of a deploy artifact is kept before it expires - the artifacts bucket is versioned, so old binaries pile up otherwise"
  type        = number
  default     = 90

  validation {
    condition     = var.artifact_version_retention_days >= 1 && var.artifact_version_retention_days <= 3650
    error_message = "artifact_version_retention_days must be between 1 and 3650 days. 0 (keep forever) is deliberately not allowed because the bill would grow forever."
  }
}

variable "abort_incomplete_multipart_days" {
  description = "Days after which an unfinished multipart upload to the artifacts bucket is aborted, so abandoned parts stop costing storage"
  type        = number
  default     = 7

  validation {
    condition     = var.abort_incomplete_multipart_days >= 1 && var.abort_incomplete_multipart_days <= 365
    error_message = "abort_incomplete_multipart_days must be between 1 and 365 days."
  }
}
