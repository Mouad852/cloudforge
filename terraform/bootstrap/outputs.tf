output "state_bucket_name" {
  description = "S3 bucket holding Terraform state for dev/prod environments"
  value       = aws_s3_bucket.state.id
}

output "terraform_plan_role_arn" {
  description = "GitHub Actions role ARN for PR-triggered terraform plan - set as the AWS_ROLE_ARN repository variable for the plan job"
  value       = module.cicd_oidc.terraform_plan_role_arn
}

output "terraform_apply_role_arn" {
  description = "GitHub Actions role ARN for main-branch terraform apply and app deploys - set as the AWS_ROLE_ARN repository variable for those jobs"
  value       = module.cicd_oidc.terraform_apply_role_arn
}
