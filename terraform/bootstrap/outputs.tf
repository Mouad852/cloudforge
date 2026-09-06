output "state_bucket_name" {
  description = "S3 bucket holding Terraform state for dev/prod environments"
  value       = aws_s3_bucket.state.id
}
