# Renders the canary script with the real target URL baked in, then zips it into the
# nodejs/node_modules/<file>.js layout the Synthetics puppeteer runtime accepts. Both are
# build artifacts (generated at plan/apply time under build/ and build.zip) - gitignored,
# not committed; the source of truth is templates/canary.js.tpl.
resource "local_file" "canary_script" {
  filename = "${path.module}/build/nodejs/node_modules/apiCanary.js"
  content = templatefile("${path.module}/templates/canary.js.tpl", {
    # Hits the ALB directly over HTTP - there is no CloudFront in front of it any more
    # (ADR-025), so the previous "hit CloudFront, never the ALB" reasoning (ADR-014)
    # no longer applies. The ALB has no HTTPS listener (ADR-025's accepted trade-off).
    target_url = "http://${var.alb_dns_name}/api/products"
  })
}

data "archive_file" "canary" {
  type        = "zip"
  source_dir  = "${path.module}/build"
  output_path = "${path.module}/build.zip"
  depends_on  = [local_file.canary_script]
}

resource "aws_iam_role" "canary" {
  name = "${local.name_prefix}-canary"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" } # canaries run as Lambda functions under the hood
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "canary" {
  name = "${local.name_prefix}-canary-least-privilege"
  role = aws_iam_role.canary.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "WriteRunArtifacts"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${var.artifacts_bucket_arn}/canary/${var.environment}/*"
      },
      {
        Sid      = "ReadBucketLocation"
        Effect   = "Allow"
        Action   = "s3:GetBucketLocation"
        Resource = var.artifacts_bucket_arn
      },
      {
        Sid      = "PutCanaryMetrics"
        Effect   = "Allow"
        Action   = "cloudwatch:PutMetricData"
        Resource = "*" # cloudwatch:PutMetricData has no ARN format - namespace condition below is the real scope
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "CloudWatchSynthetics"
          }
        }
      },
      {
        # AWS Synthetics always names the canary's log group "/aws/lambda/cwsyn-<canary-name>-<random>" -
        # this wildcard is scoped to that fixed AWS-owned prefix, not a blanket allow.
        Sid    = "CanaryLogGroup"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/cwsyn-*"
      },
    ]
  })
}

resource "aws_synthetics_canary" "api" {
  name                 = "${var.environment}-api-avail"
  artifact_s3_location = "s3://${var.artifacts_bucket_name}/canary/${var.environment}/"
  execution_role_arn   = aws_iam_role.canary.arn
  runtime_version      = var.canary_runtime_version
  handler              = "apiCanary.handler"

  zip_file = data.archive_file.canary.output_path

  schedule {
    expression = var.canary_schedule_expression
  }

  run_config {
    timeout_in_seconds = 30
  }

  start_canary = true
}
