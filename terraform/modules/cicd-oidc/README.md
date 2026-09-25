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
| [aws_iam_role_policy.terraform_plan_read_redis_auth](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.terraform_plan_sns_publish](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.terraform_apply](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.terraform_plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [tls_certificate.github_actions](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/data-sources/certificate) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_default_branch"></a> [default\_branch](#input\_default\_branch) | Branch allowed to assume the terraform-apply / app-deploy role - the plan role is open to any pull\_request against this repo | `string` | `"main"` | no |
| <a name="input_github_oidc_subject_prefix"></a> [github\_oidc\_subject\_prefix](#input\_github\_oidc\_subject\_prefix) | The literal "repo:..." prefix GitHub's OIDC tokens carry for this repository. Since GitHub enabled immutable subject claims (`use_immutable_subject`), this is no longer just "repo:${github\_repository}" - it includes GitHub's numeric owner/repo IDs, e.g. "repo:owner@12345/name@67890". Get the exact value with `gh api repos/<owner>/<repo>/actions/oidc/customization/sub` (the `sub_claim_prefix` field) - it will not change unless the repo is renamed/transferred, in which case GitHub reissues a new prefix and this must be updated to match. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_github_oidc_provider_arn"></a> [github\_oidc\_provider\_arn](#output\_github\_oidc\_provider\_arn) | The GitHub Actions OIDC provider - for reference/documentation only |
| <a name="output_terraform_apply_role_arn"></a> [terraform\_apply\_role\_arn](#output\_terraform\_apply\_role\_arn) | IAM role ARN for terraform apply (main branch) and app.yml's deploy steps - set as an AWS\_ROLE\_ARN GitHub Actions variable for those jobs |
| <a name="output_terraform_plan_role_arn"></a> [terraform\_plan\_role\_arn](#output\_terraform\_plan\_role\_arn) | IAM role ARN for the read-only PR-triggered plan step in terraform.yml - set as an AWS\_ROLE\_ARN GitHub Actions variable for that job |
<!-- END_TF_DOCS -->
