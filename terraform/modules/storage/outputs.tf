output "artifacts_bucket_name" {
  description = "Name of the deploy-artifacts bucket"
  value       = aws_s3_bucket.artifacts.bucket
}

output "artifacts_bucket_arn" {
  description = "ARN of the deploy-artifacts bucket"
  value       = aws_s3_bucket.artifacts.arn
}

output "images_bucket_id" {
  description = "Name/ID of the CDN images bucket (M6)"
  value       = aws_s3_bucket.images.id
}

output "images_bucket_arn" {
  description = "ARN of the CDN images bucket (M6)"
  value       = aws_s3_bucket.images.arn
}
