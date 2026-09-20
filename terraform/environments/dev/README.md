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
| <a name="input_alb_deletion_protection"></a> [alb\_deletion\_protection](#input\_alb\_deletion\_protection) | ALB deletion protection - on in prod, off in dev | `bool` | `false` | no |
| <a name="input_alb_log_retention_days"></a> [alb\_log\_retention\_days](#input\_alb\_log\_retention\_days) | Days ALB access logs are kept in S3 before they expire | `number` | `90` | no |
| <a name="input_alert_email"></a> [alert\_email](#input\_alert\_email) | Email address subscribed to the M7 observability SNS alerts topic | `string` | n/a | yes |
| <a name="input_app_port"></a> [app\_port](#input\_app\_port) | Port the app listens on - the ALB (edge) targets it and the app security group and service (compute) use it | `number` | `8080` | no |
| <a name="input_asg_desired_capacity"></a> [asg\_desired\_capacity](#input\_asg\_desired\_capacity) | ASG desired capacity | `number` | `1` | no |
| <a name="input_asg_max_size"></a> [asg\_max\_size](#input\_asg\_max\_size) | ASG maximum size | `number` | `2` | no |
| <a name="input_asg_min_size"></a> [asg\_min\_size](#input\_asg\_min\_size) | ASG minimum size | `number` | `1` | no |
| <a name="input_blue_weight"></a> [blue\_weight](#input\_blue\_weight) | Percentage (0-100) of ALB traffic sent to the blue fleet - shifted with green\_weight during a blue/green deploy (ADR-017) | `number` | `100` | no |
| <a name="input_cache_node_type"></a> [cache\_node\_type](#input\_cache\_node\_type) | ElastiCache node type - sized per environment through tfvars | `string` | `"cache.t4g.micro"` | no |
| <a name="input_db_allocated_storage"></a> [db\_allocated\_storage](#input\_db\_allocated\_storage) | RDS allocated storage in GB - sized per environment through tfvars | `number` | `20` | no |
| <a name="input_db_apply_immediately"></a> [db\_apply\_immediately](#input\_db\_apply\_immediately) | Apply RDS modifications immediately instead of waiting for the next maintenance window - on in dev for fast iteration, off in prod to avoid mid-day disruption | `bool` | `true` | no |
| <a name="input_db_backup_retention_period"></a> [db\_backup\_retention\_period](#input\_db\_backup\_retention\_period) | RDS automated backup retention in days | `number` | `1` | no |
| <a name="input_db_deletion_protection"></a> [db\_deletion\_protection](#input\_db\_deletion\_protection) | RDS deletion protection - on in prod, off in dev | `bool` | `false` | no |
| <a name="input_db_instance_class"></a> [db\_instance\_class](#input\_db\_instance\_class) | RDS instance class - sized per environment through tfvars | `string` | `"db.t4g.micro"` | no |
| <a name="input_db_multi_az"></a> [db\_multi\_az](#input\_db\_multi\_az) | RDS Multi-AZ deployment - on in prod, off in dev | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, prod, or test) | `string` | n/a | yes |
| <a name="input_green_asg_desired_capacity"></a> [green\_asg\_desired\_capacity](#input\_green\_asg\_desired\_capacity) | Green ASG desired capacity - 0 outside a deploy window, scaled up before shifting traffic to green | `number` | `0` | no |
| <a name="input_green_asg_max_size"></a> [green\_asg\_max\_size](#input\_green\_asg\_max\_size) | Green ASG maximum size - matches blue's ceiling so green can take over blue's full traffic during a cutover | `number` | `6` | no |
| <a name="input_green_asg_min_size"></a> [green\_asg\_min\_size](#input\_green\_asg\_min\_size) | Green ASG minimum size - 0 by default so the idle blue/green fleet costs nothing outside a deploy window (ADR-017) | `number` | `0` | no |
| <a name="input_green_weight"></a> [green\_weight](#input\_green\_weight) | Percentage (0-100) of ALB traffic sent to the green fleet - shifted with blue\_weight during a blue/green deploy (ADR-017) | `number` | `0` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type for the app ASG | `string` | `"t4g.small"` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch Logs retention, in days, for the app and VPC flow log groups | `number` | `14` | no |
| <a name="input_snapshot_identifier"></a> [snapshot\_identifier](#input\_snapshot\_identifier) | Restore this environment's DB from a snapshot instead of creating an empty one - set by `make <env>-up` after a `make <env>-down` (ADR-015) | `string` | `null` | no |

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
