output "alb_dns_name" {
  description = "Public DNS name of the ALB - the public entry point (ADR-025: this ALB is the edge, no CloudFront in front of it)"
  value       = aws_lb.app.dns_name
}

output "alb_arn" {
  value = aws_lb.app.arn
}

output "alb_arn_suffix" {
  description = "Shortened ALB identifier CloudWatch metrics key on (not the full ARN - AWS/ApplicationELB dimension quirk)"
  value       = aws_lb.app.arn_suffix
}

output "blue_target_group_arn" {
  value = aws_lb_target_group.blue.arn
}

output "blue_target_group_arn_suffix" {
  description = "Shortened target-group identifier for the CloudWatch TargetGroup dimension"
  value       = aws_lb_target_group.blue.arn_suffix
}

output "green_target_group_arn" {
  description = "Unused until M8's blue/green cutover"
  value       = aws_lb_target_group.green.arn
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}

output "waf_web_acl_arn" {
  value = aws_wafv2_web_acl.alb.arn
}
