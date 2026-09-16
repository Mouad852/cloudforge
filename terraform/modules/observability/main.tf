data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "${var.environment}-cloudforge"
}

resource "aws_sns_topic" "alerts" {
  name              = "${local.name_prefix}-alerts"
  kms_master_key_id = "alias/aws/sns" # AWS-managed key - free, satisfies checkov CKV_AWS_26
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# CloudWatch alarms can only target an SNS topic in their own region. The
# billing alarm below is forced into us-east-1 (AWS/Billing metrics only
# publish there), while the shared alerts topic above lives in this
# environment's primary region - a second, us-east-1-only topic is the only
# way to actually deliver its notifications.
resource "aws_sns_topic" "billing_alerts" {
  provider          = aws.use1
  name              = "${local.name_prefix}-billing-alerts"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "billing_alerts_email" {
  provider  = aws.use1
  topic_arn = aws_sns_topic.billing_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_log_metric_filter" "error_count" {
  name           = "${local.name_prefix}-error-count"
  log_group_name = var.app_log_group_name
  pattern        = "{ $.level = \"ERROR\" }"

  metric_transformation {
    name          = "ErrorCount"
    namespace     = "CloudForge/App"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "exception_count" {
  name           = "${local.name_prefix}-exception-count"
  log_group_name = var.app_log_group_name
  # app/main.go's withRequestLogging emits one JSON line per request with msg="request"
  # and the real HTTP status - this catches responses that reached a client as a 5xx,
  # a distinct signal from error_count above (app-level log.Error calls that may never
  # surface as a failed response, e.g. a logged-and-recovered condition).
  pattern = "{ $.msg = \"request\" && $.status >= 500 }"

  metric_transformation {
    name          = "ExceptionCount"
    namespace     = "CloudForge/App"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}
