output "app_security_group_id" {
  description = "App instances' security group ID - RDS/Redis security groups allow ingress from this only"
  value       = aws_security_group.app.id
}
