variable "environment" {
  description = "Environment name (dev, prod, or test), used in resource naming/tags"
  type        = string

  validation {
    condition     = contains(["dev", "prod", "test"], var.environment)
    error_message = "environment must be one of: dev, prod, test."
  }
}

variable "alert_email" {
  description = "Email address subscribed to the alerts SNS topic - receives every alarm and the composite service-degraded alarm"
  type        = string
}

# --- Identifiers alarms attach to, wired from other modules' outputs ---

variable "alb_arn_suffix" {
  description = "ALB arn_suffix (module.edge.alb_arn_suffix) - CloudWatch AWS/ApplicationELB LoadBalancer dimension"
  type        = string
}

variable "target_group_arn_suffix" {
  description = "Target group arn_suffix (module.edge.blue_target_group_arn_suffix) - CloudWatch TargetGroup dimension"
  type        = string
}

variable "asg_name" {
  description = "Auto Scaling Group name (module.compute.asg_name)"
  type        = string
}

variable "app_log_group_name" {
  description = "CloudWatch Logs group receiving structured app logs (module.compute.app_log_group_name) - metric filter source"
  type        = string
}

variable "db_instance_id" {
  description = "RDS DBInstanceIdentifier (module.database.instance_id)"
  type        = string
}

variable "redis_replication_group_id" {
  description = "ElastiCache replication group ID (module.cache.replication_group_id) - node is single-cluster, so CacheClusterId = \"<this>-001\""
  type        = string
}

variable "artifacts_bucket_name" {
  description = "S3 bucket (module.storage.artifacts_bucket_name) the Synthetics canary writes its run artifacts (screenshots, HAR files) to, under a canary/ prefix"
  type        = string
}

variable "artifacts_bucket_arn" {
  description = "ARN of the same bucket, for the canary execution role's IAM policy"
  type        = string
}

variable "cloudfront_domain_name" {
  description = "CloudFront distribution domain (module.edge.cloudfront_domain_name) - the canary hits this, never the ALB directly (ADR-014: the ALB 403s anything that doesn't arrive via CloudFront with the secret origin header)"
  type        = string
}

# --- Alarm thresholds ---
# Fixed values here come straight from PLAN.md §M7's alarm table. Where the table gives a
# threshold but not a duration, a conservative default is chosen and noted inline - there was
# nothing to preserve consistency with, so these are this module's call, not a transcription.

variable "rds_max_connections_threshold" {
  description = "Absolute DatabaseConnections count alarm threshold. Derived from db.t4g.micro's default max_connections (~112, from RDS's memory-based formula) - 80% of that is ~90"
  type        = number
  default     = 90
}

variable "billing_budget_usd" {
  description = "AWS/Billing EstimatedCharges alarm threshold - matches the $20 AWS Budget from PLAN.md §4"
  type        = number
  default     = 20
}

variable "canary_schedule_expression" {
  description = "How often the Synthetics canary runs"
  type        = string
  default     = "rate(5 minutes)"
}

variable "canary_runtime_version" {
  description = "Synthetics canary Node.js/Puppeteer runtime version"
  type        = string
  default     = "syn-nodejs-puppeteer-9.1"
}
