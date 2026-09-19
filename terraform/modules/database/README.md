# database

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 3.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.64.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_db_instance.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) | resource |
| [aws_db_parameter_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_parameter_group) | resource |
| [aws_db_subnet_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_route53_record.db](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_security_group.rds](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [random_id.final_snapshot_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allocated_storage"></a> [allocated\_storage](#input\_allocated\_storage) | Allocated storage in GB | `number` | `20` | no |
| <a name="input_app_security_group_id"></a> [app\_security\_group\_id](#input\_app\_security\_group\_id) | App instances' security group ID - the only allowed ingress source | `string` | n/a | yes |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | Apply modifications right away instead of waiting for the next maintenance window - on in dev for fast iteration, should be off in prod to avoid mid-day disruption | `bool` | `true` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | Automated backup retention in days | `number` | `1` | no |
| <a name="input_data_subnet_ids"></a> [data\_subnet\_ids](#input\_data\_subnet\_ids) | Data-tier subnet IDs (both AZs) for the DB subnet group | `list(string)` | n/a | yes |
| <a name="input_db_name"></a> [db\_name](#input\_db\_name) | Initial database name | `string` | `"cloudstore"` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | Deletion protection - on in prod, off in dev | `bool` | `false` | no |
| <a name="input_dns_ttl_seconds"></a> [dns\_ttl\_seconds](#input\_dns\_ttl\_seconds) | TTL, in seconds, of the private DNS CNAME the app connects through - short enough that a replaced RDS instance is picked up quickly | `number` | `300` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | PostgreSQL engine version | `string` | `"16.15"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, prod, or test), used in resource naming/tags | `string` | n/a | yes |
| <a name="input_instance_class"></a> [instance\_class](#input\_instance\_class) | RDS instance class | `string` | `"db.t4g.micro"` | no |
| <a name="input_master_username"></a> [master\_username](#input\_master\_username) | Master username - the password itself is AWS-managed (ADR-009), never set here | `string` | `"cloudforge_admin"` | no |
| <a name="input_multi_az"></a> [multi\_az](#input\_multi\_az) | Multi-AZ deployment - on in prod, off in dev | `bool` | `false` | no |
| <a name="input_private_zone_id"></a> [private\_zone\_id](#input\_private\_zone\_id) | Route 53 private hosted zone ID (ADR-013) - the DNS record lives here | `string` | n/a | yes |
| <a name="input_snapshot_identifier"></a> [snapshot\_identifier](#input\_snapshot\_identifier) | Restore from this snapshot instead of creating an empty DB - set to a final snapshot ID to bring data back after a dev-down (ADR-015) | `string` | `null` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID the RDS security group lives in | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_db_address"></a> [db\_address](#output\_db\_address) | RDS instance hostname only, no port - what Route 53's CNAME will point at |
| <a name="output_db_endpoint"></a> [db\_endpoint](#output\_db\_endpoint) | RDS instance endpoint (host:port) |
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | RDS DBInstanceIdentifier - CloudWatch alarm dimension |
| <a name="output_master_user_secret_arn"></a> [master\_user\_secret\_arn](#output\_master\_user\_secret\_arn) | Secrets Manager ARN holding the AWS-managed master password (ADR-009) |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | RDS security group ID |
<!-- END_TF_DOCS -->
