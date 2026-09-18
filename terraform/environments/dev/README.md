# dev

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_cache"></a> [cache](#module\_cache) | ../../modules/cache | n/a |
| <a name="module_compute"></a> [compute](#module\_compute) | ../../modules/compute | n/a |
| <a name="module_database"></a> [database](#module\_database) | ../../modules/database | n/a |
| <a name="module_edge"></a> [edge](#module\_edge) | ../../modules/edge | n/a |
| <a name="module_network"></a> [network](#module\_network) | ../../modules/network | n/a |
| <a name="module_observability"></a> [observability](#module\_observability) | ../../modules/observability | n/a |
| <a name="module_storage"></a> [storage](#module\_storage) | ../../modules/storage | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alert_email"></a> [alert\_email](#input\_alert\_email) | Email address subscribed to the M7 observability SNS alerts topic | `string` | n/a | yes |
| <a name="input_snapshot_identifier"></a> [snapshot\_identifier](#input\_snapshot\_identifier) | Restore dev-cloudforge-db from this snapshot instead of creating an empty one - set by `make dev-up` after a `make dev-down` (ADR-015) | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | n/a |
| <a name="output_alerts_sns_topic_arn"></a> [alerts\_sns\_topic\_arn](#output\_alerts\_sns\_topic\_arn) | n/a |
| <a name="output_artifact_key"></a> [artifact\_key](#output\_artifact\_key) | n/a |
| <a name="output_artifacts_bucket_name"></a> [artifacts\_bucket\_name](#output\_artifacts\_bucket\_name) | n/a |
| <a name="output_asg_name"></a> [asg\_name](#output\_asg\_name) | n/a |
| <a name="output_cloudfront_domain_name"></a> [cloudfront\_domain\_name](#output\_cloudfront\_domain\_name) | n/a |
| <a name="output_golden_signals_dashboard_name"></a> [golden\_signals\_dashboard\_name](#output\_golden\_signals\_dashboard\_name) | n/a |
| <a name="output_images_bucket_name"></a> [images\_bucket\_name](#output\_images\_bucket\_name) | n/a |
| <a name="output_launch_template_id"></a> [launch\_template\_id](#output\_launch\_template\_id) | n/a |
| <a name="output_origin_secret_header_name"></a> [origin\_secret\_header\_name](#output\_origin\_secret\_header\_name) | n/a |
| <a name="output_origin_secret_header_value"></a> [origin\_secret\_header\_value](#output\_origin\_secret\_header\_value) | n/a |
| <a name="output_redis_primary_endpoint"></a> [redis\_primary\_endpoint](#output\_redis\_primary\_endpoint) | n/a |
| <a name="output_slo_dashboard_name"></a> [slo\_dashboard\_name](#output\_slo\_dashboard\_name) | n/a |
| <a name="output_subnet_ids"></a> [subnet\_ids](#output\_subnet\_ids) | n/a |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | n/a |
<!-- END_TF_DOCS -->
