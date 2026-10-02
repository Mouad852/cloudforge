# bootstrap

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.6 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |
| <a name="provider_aws.us_east_1"></a> [aws.us\_east\_1](#provider\_aws.us\_east\_1) | 5.100.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.1 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_cicd_oidc"></a> [cicd\_oidc](#module\_cicd\_oidc) | ../modules/cicd-oidc | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_accessanalyzer_analyzer.account](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/accessanalyzer_analyzer) | resource |
| [aws_accessanalyzer_archive_rule.github_actions_roles](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/accessanalyzer_archive_rule) | resource |
| [aws_budgets_budget.monthly](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget) | resource |
| [aws_ce_cost_allocation_tag.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ce_cost_allocation_tag) | resource |
| [aws_cloudtrail.management_events](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudtrail) | resource |
| [aws_ebs_encryption_by_default.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_encryption_by_default) | resource |
| [aws_s3_bucket.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.cloudtrail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_lifecycle_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_policy.cloudtrail](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_policy.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [random_id.state_bucket_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_budget_alert_email"></a> [budget\_alert\_email](#input\_budget\_alert\_email) | Email address the budget alerts go to. Not committed: pass it with -var or in the gitignored terraform.tfvars | `string` | n/a | yes |
| <a name="input_monthly_budget_usd"></a> [monthly\_budget\_usd](#input\_monthly\_budget\_usd) | Monthly cost budget in USD, measured before credits. Set close to the credit left, so the 50/80/95% alerts arrive while it still lasts | `string` | `"60"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region for the state bucket | `string` | `"eu-west-3"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_state_bucket_name"></a> [state\_bucket\_name](#output\_state\_bucket\_name) | S3 bucket holding Terraform state for dev/prod environments |
| <a name="output_terraform_apply_role_arn"></a> [terraform\_apply\_role\_arn](#output\_terraform\_apply\_role\_arn) | GitHub Actions role ARN for main-branch terraform apply and app deploys - set as the AWS\_ROLE\_ARN repository variable for those jobs |
| <a name="output_terraform_plan_role_arn"></a> [terraform\_plan\_role\_arn](#output\_terraform\_plan\_role\_arn) | GitHub Actions role ARN for PR-triggered terraform plan - set as the AWS\_ROLE\_ARN repository variable for the plan job |
<!-- END_TF_DOCS -->
