# dev

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_compute"></a> [compute](#module\_compute) | ../../modules/compute | n/a |
| <a name="module_database"></a> [database](#module\_database) | ../../modules/database | n/a |
| <a name="module_edge"></a> [edge](#module\_edge) | ../../modules/edge | n/a |
| <a name="module_network"></a> [network](#module\_network) | ../../modules/network | n/a |
| <a name="module_storage"></a> [storage](#module\_storage) | ../../modules/storage | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_instance_profile.ssm_test_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.ssm_test_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ssm_test_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_instance.ssm_test](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_security_group.ssm_test_instance](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_ami.al2023](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_snapshot_identifier"></a> [snapshot\_identifier](#input\_snapshot\_identifier) | Restore dev-cloudforge-db from this snapshot instead of creating an empty one - set by `make dev-up` after a `make dev-down` (ADR-015) | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | n/a |
| <a name="output_subnet_ids"></a> [subnet\_ids](#output\_subnet\_ids) | n/a |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | n/a |
<!-- END_TF_DOCS -->
