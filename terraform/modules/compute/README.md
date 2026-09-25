# compute

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.63.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_autoscaling_group.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_autoscaling_group.app_green](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_autoscaling_lifecycle_hook.terminating](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_lifecycle_hook) | resource |
| [aws_autoscaling_lifecycle_hook.terminating_green](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_lifecycle_hook) | resource |
| [aws_autoscaling_policy.cpu_target_tracking](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_policy) | resource |
| [aws_cloudwatch_log_group.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_instance_profile.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.ssm](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_launch_template.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_security_group.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_ami.al2023_arm64](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_default_tags.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/default_tags) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alb_security_group_id"></a> [alb\_security\_group\_id](#input\_alb\_security\_group\_id) | ALB's security group ID (modules/edge) - the app SG allows inbound only from this, M4 | `string` | n/a | yes |
| <a name="input_app_port"></a> [app\_port](#input\_app\_port) | Port the app listens on | `number` | `8080` | no |
| <a name="input_app_subnet_ids"></a> [app\_subnet\_ids](#input\_app\_subnet\_ids) | App-tier subnet IDs (both Azs) the ASG launches into | `list(string)` | n/a | yes |
| <a name="input_artifact_key"></a> [artifact\_key](#input\_artifact\_key) | S3 key of the app binary within the artifacts bucket | `string` | `"cloudstore-api/cloudstore-api"` | no |
| <a name="input_artifacts_bucket_arn"></a> [artifacts\_bucket\_arn](#input\_artifacts\_bucket\_arn) | ARN of the S3 bucket the app binary is pulled from (modules/storage) | `string` | n/a | yes |
| <a name="input_artifacts_bucket_name"></a> [artifacts\_bucket\_name](#input\_artifacts\_bucket\_name) | Name of the S3 bucket the app binary is pulled from (modules/storage) | `string` | n/a | yes |
| <a name="input_asg_desired_capacity"></a> [asg\_desired\_capacity](#input\_asg\_desired\_capacity) | ASG desired capacity | `number` | `2` | no |
| <a name="input_asg_max_size"></a> [asg\_max\_size](#input\_asg\_max\_size) | ASG maximum size | `number` | `6` | no |
| <a name="input_asg_min_size"></a> [asg\_min\_size](#input\_asg\_min\_size) | ASG minimum size | `number` | `2` | no |
| <a name="input_cpu_target_percent"></a> [cpu\_target\_percent](#input\_cpu\_target\_percent) | Average CPU utilisation (%) the blue ASG's target-tracking policy scales towards | `number` | `60` | no |
| <a name="input_data_tier_cidr_blocks"></a> [data\_tier\_cidr\_blocks](#input\_data\_tier\_cidr\_blocks) | Data-tier subnet CIDRs - the app SG's egress for RDS/Redis is scoped to these, not the whole VPC | `list(string)` | n/a | yes |
| <a name="input_db_secret_arn"></a> [db\_secret\_arn](#input\_db\_secret\_arn) | Secrets Manager ARN for the RDS master password (ADR-009) - empty string means no database configured yet | `string` | `""` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, prod, or test), used in resource naming/tags | `string` | n/a | yes |
| <a name="input_green_asg_desired_capacity"></a> [green\_asg\_desired\_capacity](#input\_green\_asg\_desired\_capacity) | Green ASG desired capacity - 0 by default, scaled up only during a blue/green deploy | `number` | `0` | no |
| <a name="input_green_asg_max_size"></a> [green\_asg\_max\_size](#input\_green\_asg\_max\_size) | Green ASG maximum size - matches blue's ceiling so it can take over blue's full traffic during a cutover | `number` | `6` | no |
| <a name="input_green_asg_min_size"></a> [green\_asg\_min\_size](#input\_green\_asg\_min\_size) | Green ASG minimum size - 0 by default so the idle blue/green fleet costs nothing outside a deploy window | `number` | `0` | no |
| <a name="input_green_target_group_arns"></a> [green\_target\_group\_arns](#input\_green\_target\_group\_arns) | ALB green target group ARNs to attach the green ASG to | `list(string)` | `[]` | no |
| <a name="input_health_check_grace_period"></a> [health\_check\_grace\_period](#input\_health\_check\_grace\_period) | Seconds the blue and green ASGs wait after an instance launches before ELB health checks can replace it - must cover the bootstrap script (S3 download, secrets, app start) | `number` | `300` | no |
| <a name="input_images_bucket_name"></a> [images\_bucket\_name](#input\_images\_bucket\_name) | Name of the M6 images bucket. Not created yet - the IAM role is pre-scoped to this name so M6 needs no policy changes, only rewiring this variable to the real bucket once it exists. | `string` | n/a | yes |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type (Graviton/arm64, ADR-003) | `string` | `"t4g.micro"` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | CloudWatch Logs retention, in days, for the app log group | `number` | `14` | no |
| <a name="input_redis_addr"></a> [redis\_addr](#input\_redis\_addr) | Redis host:port app instances connect to (M6) | `string` | `"cache.cloudforge.internal:6379"` | no |
| <a name="input_redis_secret_arn"></a> [redis\_secret\_arn](#input\_redis\_secret\_arn) | Secrets Manager ARN for the Redis AUTH token (M6) - empty string means no cache configured yet | `string` | `""` | no |
| <a name="input_redis_tls_server_name"></a> [redis\_tls\_server\_name](#input\_redis\_tls\_server\_name) | Real ElastiCache hostname for TLS certificate verification (M6) - differs from redis\_addr, which is our own Route 53 CNAME (ADR-013); empty string means no cache configured yet | `string` | `""` | no |
| <a name="input_root_volume_size_gb"></a> [root\_volume\_size\_gb](#input\_root\_volume\_size\_gb) | Size in GiB of each app instance's encrypted root volume | `number` | `30` | no |
| <a name="input_target_group_arns"></a> [target\_group\_arns](#input\_target\_group\_arns) | ALB target group ARNs to attach the ASG to - M4 wires this in; empty until then | `list(string)` | `[]` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID the compute layer runs in | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_app_log_group_arn"></a> [app\_log\_group\_arn](#output\_app\_log\_group\_arn) | ARN of the app log group |
| <a name="output_app_log_group_name"></a> [app\_log\_group\_name](#output\_app\_log\_group\_name) | CloudWatch Logs group receiving structured app logs - source for M7 metric filters |
| <a name="output_app_security_group_id"></a> [app\_security\_group\_id](#output\_app\_security\_group\_id) | App instances' security group ID - RDS/Redis security groups allow ingress from this only |
| <a name="output_artifact_key"></a> [artifact\_key](#output\_artifact\_key) | S3 key deploy tooling uploads the new app binary to before triggering an instance refresh |
| <a name="output_asg_name"></a> [asg\_name](#output\_asg\_name) | Auto Scaling Group name - CloudWatch alarm dimension (GroupInServiceInstances, ASGAverageCPUUtilization) |
| <a name="output_green_asg_name"></a> [green\_asg\_name](#output\_green\_asg\_name) | Green Auto Scaling Group name - blue/green deploy tooling scales this during a cutover |
| <a name="output_launch_template_id"></a> [launch\_template\_id](#output\_launch\_template\_id) | Launch template ID - deploy tooling creates a new version against this before an instance refresh |
<!-- END_TF_DOCS -->
