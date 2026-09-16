output "sns_topic_arn" {
  description = "Alerts SNS topic ARN - every regional alarm and the composite alarm publish here (the billing alarm uses its own us-east-1 topic - see billing_sns_topic_arn)"
  value       = aws_sns_topic.alerts.arn
}

output "billing_sns_topic_arn" {
  description = "Billing alarm's dedicated us-east-1 SNS topic ARN - CloudWatch alarms can't target a topic outside their own region"
  value       = aws_sns_topic.billing_alerts.arn
}

output "golden_signals_dashboard_name" {
  description = "Four Golden Signals dashboard name"
  value       = aws_cloudwatch_dashboard.golden_signals.dashboard_name
}

output "slo_dashboard_name" {
  description = "SLO dashboard name"
  value       = aws_cloudwatch_dashboard.slo.dashboard_name
}

output "canary_name" {
  description = "Synthetics canary name"
  value       = aws_synthetics_canary.api.name
}

output "composite_alarm_name" {
  description = "The \"service degraded\" composite alarm name"
  value       = aws_cloudwatch_composite_alarm.service_degraded.alarm_name
}
