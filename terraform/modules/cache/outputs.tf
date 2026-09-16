output "redis_primary_endpoint" {
  description = "ElastiCache Redis primary endpoint address, no port"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "redis_port" {
  description = "Redis port"
  value       = aws_elasticache_replication_group.main.port
}

output "security_group_id" {
  description = "Redis security group ID"
  value       = aws_security_group.redis.id
}

output "auth_secret_arn" {
  description = "Secrets Manager ARN holding the Redis AUTH token"
  value       = aws_secretsmanager_secret.redis_auth.arn
}

output "replication_group_id" {
  description = "ElastiCache replication group ID - CloudWatch alarm dimension (CacheClusterId)"
  value       = aws_elasticache_replication_group.main.id
}
