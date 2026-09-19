# cache

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_elasticache_replication_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_replication_group) | resource |
| [aws_elasticache_subnet_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_subnet_group) | resource |
| [aws_route53_record.cache](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_secretsmanager_secret.redis_auth](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret) | resource |
| [aws_secretsmanager_secret_version.redis_auth](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_version) | resource |
| [aws_security_group.redis](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [random_password.redis_auth](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_app_security_group_id"></a> [app\_security\_group\_id](#input\_app\_security\_group\_id) | App instances' security group ID - the only allowed ingress source | `string` | n/a | yes |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply\_immediately) | Apply modifications right away instead of waiting for the next maintenance window - on in dev for fast iteration | `bool` | `true` | no |
| <a name="input_data_subnet_ids"></a> [data\_subnet\_ids](#input\_data\_subnet\_ids) | Data-tier subnet IDs (both AZs) for the ElastiCache subnet group | `list(string)` | n/a | yes |
| <a name="input_dns_ttl_seconds"></a> [dns\_ttl\_seconds](#input\_dns\_ttl\_seconds) | TTL, in seconds, of the private DNS CNAME the app connects through - short enough that a replaced Redis endpoint is picked up quickly | `number` | `300` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | Redis engine version | `string` | `"7.1"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, prod, or test), used in resource naming/tags | `string` | n/a | yes |
| <a name="input_node_type"></a> [node\_type](#input\_node\_type) | ElastiCache node type | `string` | `"cache.t4g.micro"` | no |
| <a name="input_private_zone_id"></a> [private\_zone\_id](#input\_private\_zone\_id) | Route 53 private hosted zone ID (ADR-013) - the DNS record lives here | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID the Redis security group lives in | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_auth_secret_arn"></a> [auth\_secret\_arn](#output\_auth\_secret\_arn) | Secrets Manager ARN holding the Redis AUTH token |
| <a name="output_redis_port"></a> [redis\_port](#output\_redis\_port) | Redis port |
| <a name="output_redis_primary_endpoint"></a> [redis\_primary\_endpoint](#output\_redis\_primary\_endpoint) | ElastiCache Redis primary endpoint address, no port |
| <a name="output_replication_group_id"></a> [replication\_group\_id](#output\_replication\_group\_id) | ElastiCache replication group ID - CloudWatch alarm dimension (CacheClusterId) |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Redis security group ID |
<!-- END_TF_DOCS -->
