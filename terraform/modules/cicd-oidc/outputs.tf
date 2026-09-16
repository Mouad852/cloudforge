output "terraform_plan_role_arn" {
  description = "IAM role ARN for the read-only PR-triggered plan step in terraform.yml - set as an AWS_ROLE_ARN GitHub Actions variable for that job"
  value       = aws_iam_role.terraform_plan.arn
}

output "terraform_apply_role_arn" {
  description = "IAM role ARN for terraform apply (main branch) and app.yml's deploy steps - set as an AWS_ROLE_ARN GitHub Actions variable for those jobs"
  value       = aws_iam_role.terraform_apply.arn
}

output "github_oidc_provider_arn" {
  description = "The GitHub Actions OIDC provider - for reference/documentation only"
  value       = aws_iam_openid_connect_provider.github_actions.arn
}
