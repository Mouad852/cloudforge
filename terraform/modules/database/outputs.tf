output "db_endpoint" {
  description = "RDS instance endpoint (host:port)"
  value       = aws_db_instance.main.endpoint
}

output "db_address" {
  description = "RDS instance hostname only, no port - what Route 53's CNAME will point at"
  value       = aws_db_instance.main.address
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN holding the AWS-managed master password (ADR-009)"
  value       = aws_db_instance.main.master_user_secret[0].secret_arn
}

output "security_group_id" {
  description = "RDS security group ID"
  value       = aws_security_group.rds.id
}
