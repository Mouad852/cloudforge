output "sns_topic_arn" {
  description = "Alerts SNS topic ARN - every alarm and the composite alarm publish here"
  value       = aws_sns_topic.alerts.arn
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
