output "app_security_group_id" {
  description = "App instances' security group ID - RDS/Redis security groups allow ingress from this only"
  value       = aws_security_group.app.id
}

output "asg_name" {
  description = "Auto Scaling Group name - CloudWatch alarm dimension (GroupInServiceInstances, ASGAverageCPUUtilization)"
  value       = aws_autoscaling_group.app.name
}

output "app_log_group_name" {
  description = "CloudWatch Logs group receiving structured app logs - source for M7 metric filters"
  value       = aws_cloudwatch_log_group.app.name
}

output "app_log_group_arn" {
  description = "ARN of the app log group"
  value       = aws_cloudwatch_log_group.app.arn
}

output "green_asg_name" {
  description = "Green Auto Scaling Group name - blue/green deploy tooling scales this during a cutover"
  value       = aws_autoscaling_group.app_green.name
}

output "launch_template_id" {
  description = "Launch template ID - deploy tooling creates a new version against this before an instance refresh"
  value       = aws_launch_template.app.id
}

output "artifact_key" {
  description = "S3 key deploy tooling uploads the new app binary to before triggering an instance refresh"
  value       = var.artifact_key
}
