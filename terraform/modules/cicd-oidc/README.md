# cicd-oidc

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | ~> 4.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | 4.4.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_openid_connect_provider.github_actions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.terraform_apply](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.terraform_plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.terraform_apply_iam_scoped](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.terraform_apply](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.terraform_plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [tls_certificate.github_actions](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/data-sources/certificate) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_default_branch"></a> [default\_branch](#input\_default\_branch) | Branch allowed to assume the terraform-apply / app-deploy role - the plan role is open to any pull\_request against this repo | `string` | `"main"` | no |
| <a name="input_github_repository"></a> [github\_repository](#input\_github\_repository) | GitHub repo this OIDC provider trusts, as "owner/repo" - only workflow runs from this exact repo can assume the roles below | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_github_oidc_provider_arn"></a> [github\_oidc\_provider\_arn](#output\_github\_oidc\_provider\_arn) | The GitHub Actions OIDC provider - for reference/documentation only |
| <a name="output_terraform_apply_role_arn"></a> [terraform\_apply\_role\_arn](#output\_terraform\_apply\_role\_arn) | IAM role ARN for terraform apply (main branch) and app.yml's deploy steps - set as an AWS\_ROLE\_ARN GitHub Actions variable for those jobs |
| <a name="output_terraform_plan_role_arn"></a> [terraform\_plan\_role\_arn](#output\_terraform\_plan\_role\_arn) | IAM role ARN for the read-only PR-triggered plan step in terraform.yml - set as an AWS\_ROLE\_ARN GitHub Actions variable for that job |
<!-- END_TF_DOCS -->
