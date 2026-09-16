# Four Golden Signals: latency, traffic, errors, saturation - the standard SRE framework
# for "what do I look at first when something's wrong" (Google SRE book). This is the
# day-to-day operational view; the SLO dashboard below is the compliance view.
resource "aws_cloudwatch_dashboard" "golden_signals" {
  dashboard_name = "${local.name_prefix}-golden-signals"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# Four Golden Signals — ${var.environment}"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 24
        height = 6
        properties = {
          title  = "Latency — TargetResponseTime"
          view   = "timeSeries"
          region = "eu-west-3"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "Average", label = "avg" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p95", label = "p95" }],
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p99", label = "p99" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "Traffic — RequestCount"
          view   = "timeSeries"
          region = "eu-west-3"
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "Errors — ALB + app-level"
          view   = "timeSeries"
          region = "eu-west-3"
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count", "LoadBalancer", var.alb_arn_suffix, { label = "ALB 4xx" }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { label = "ALB 5xx" }],
            ["CloudForge/App", "ErrorCount", { label = "app log level=ERROR" }],
            ["CloudForge/App", "ExceptionCount", { label = "app responses >=500" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "Saturation — compute"
          view   = "timeSeries"
          region = "eu-west-3"
          period = 60
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name, { stat = "Average", label = "EC2 CPU %" }],
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", var.asg_name, { stat = "Average", label = "InService" }],
            ["AWS/AutoScaling", "GroupDesiredCapacity", "AutoScalingGroupName", var.asg_name, { stat = "Average", label = "Desired" }],
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 13
        width  = 12
        height = 6
        properties = {
          title  = "Saturation — data tier"
          view   = "timeSeries"
          region = "eu-west-3"
          period = 60
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", var.db_instance_id, { stat = "Average", label = "RDS CPU %" }],
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", var.db_instance_id, { stat = "Average", label = "RDS connections" }],
            ["AWS/ElastiCache", "DatabaseMemoryUsagePercentage", "CacheClusterId", "${var.redis_replication_group_id}-001", { stat = "Average", label = "Redis memory %" }],
            ["AWS/ElastiCache", "Evictions", "CacheClusterId", "${var.redis_replication_group_id}-001", { stat = "Sum", label = "Redis evictions" }],
          ]
        }
      },
    ]
  })
}

# The compliance view: each SLI from PLAN.md §10 plotted against its SLO target line, so
# "are we inside budget" is a glance, not a spreadsheet.
resource "aws_cloudwatch_dashboard" "slo" {
  dashboard_name = "${local.name_prefix}-slo"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "# SLO dashboard — ${var.environment}  (targets: docs/observability/slo.md)"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 24
        height = 6
        properties = {
          title  = "Availability SLI — canary SuccessPercent (SLO: 99.5%)"
          view   = "timeSeries"
          region = "eu-west-3"
          period = 300
          yAxis  = { left = { min = 0, max = 100 } }
          metrics = [
            ["CloudWatchSynthetics", "SuccessPercent", "CanaryName", aws_synthetics_canary.api.name, { stat = "Average" }],
          ]
          annotations = {
            horizontal = [
              { label = "SLO: 99.5%", value = 99.5 },
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "Latency SLI — TargetResponseTime p99 (SLO: < 500ms for 99% of requests)"
          view   = "timeSeries"
          region = "eu-west-3"
          period = 300
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p99" }],
          ]
          annotations = {
            horizontal = [
              { label = "SLO: 0.5s (500ms)", value = 0.5 },
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 7
        width  = 12
        height = 6
        properties = {
          title  = "Correctness SLI — 5xx rate (SLO: < 0.1% of requests)"
          view   = "timeSeries"
          region = "eu-west-3"
          period = 300
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix, { id = "reqs", stat = "Sum", visible = false }],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", var.alb_arn_suffix, { id = "err5xx", stat = "Sum", visible = false }],
            [{ expression = "100 * (err5xx / reqs)", label = "5xx rate (%)", id = "errRate" }],
          ]
          annotations = {
            horizontal = [
              { label = "SLO: 0.1%", value = 0.1 },
            ]
          }
        }
      },
    ]
  })
}
