output "artifacts_bucket_name" {
  description = "Name of the deploy-artifacts bucket"
  value       = aws_s3_bucket.artifacts.bucket
}

output "artifacts_bucket_arn" {
  description = "ARN of the deploy-artifacts bucket"
  value       = aws_s3_bucket.artifacts.arn
}
