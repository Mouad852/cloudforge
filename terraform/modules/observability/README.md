# observability

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.11 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | ~> 2.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |
| <a name="requirement_local"></a> [local](#requirement\_local) | ~> 2.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_archive"></a> [archive](#provider\_archive) | 2.8.1 |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |
| <a name="provider_aws.use1"></a> [aws.use1](#provider\_aws.use1) | 5.100.0 |
| <a name="provider_local"></a> [local](#provider\_local) | 2.9.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_composite_alarm.service_degraded](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_composite_alarm) | resource |
| [aws_cloudwatch_dashboard.golden_signals](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard) | resource |
| [aws_cloudwatch_dashboard.slo](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard) | resource |
| [aws_cloudwatch_log_metric_filter.error_count](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_metric_filter) | resource |
| [aws_cloudwatch_log_metric_filter.exception_count](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_metric_filter) | resource |
| [aws_cloudwatch_metric_alarm.alb_5xx](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.alb_latency_p95](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.alb_unhealthy_hosts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.asg_in_service_instances](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.billing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.ec2_cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.rds_connections](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.rds_cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.rds_free_storage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.redis_evictions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.redis_memory](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_iam_role.canary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.canary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_sns_topic.alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic.billing_alerts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_subscription.alerts_email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_sns_topic_subscription.billing_alerts_email](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |
| [aws_synthetics_canary.api](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/synthetics_canary) | resource |
| [local_file.canary_script](https://registry.terraform.io/providers/hashicorp/local/latest/docs/resources/file) | resource |
| [archive_file.canary](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_alb_arn_suffix"></a> [alb\_arn\_suffix](#input\_alb\_arn\_suffix) | ALB arn\_suffix (module.edge.alb\_arn\_suffix) - CloudWatch AWS/ApplicationELB LoadBalancer dimension | `string` | n/a | yes |
| <a name="input_alb_dns_name"></a> [alb\_dns\_name](#input\_alb\_dns\_name) | ALB public DNS name (module.edge.alb\_dns\_name) - the canary hits this directly now that the ALB is the public edge itself (ADR-025 supersedes ADR-014's CloudFront-only lockdown) | `string` | n/a | yes |
| <a name="input_alert_email"></a> [alert\_email](#input\_alert\_email) | Email address subscribed to the alerts SNS topic - receives every alarm and the composite service-degraded alarm | `string` | n/a | yes |
| <a name="input_app_log_group_name"></a> [app\_log\_group\_name](#input\_app\_log\_group\_name) | CloudWatch Logs group receiving structured app logs (module.compute.app\_log\_group\_name) - metric filter source | `string` | n/a | yes |
| <a name="input_artifacts_bucket_arn"></a> [artifacts\_bucket\_arn](#input\_artifacts\_bucket\_arn) | ARN of the same bucket, for the canary execution role's IAM policy | `string` | n/a | yes |
| <a name="input_artifacts_bucket_name"></a> [artifacts\_bucket\_name](#input\_artifacts\_bucket\_name) | S3 bucket (module.storage.artifacts\_bucket\_name) the Synthetics canary writes its run artifacts (screenshots, HAR files) to, under a canary/ prefix | `string` | n/a | yes |
| <a name="input_asg_name"></a> [asg\_name](#input\_asg\_name) | Auto Scaling Group name (module.compute.asg\_name) | `string` | n/a | yes |
| <a name="input_billing_budget_usd"></a> [billing\_budget\_usd](#input\_billing\_budget\_usd) | AWS/Billing EstimatedCharges alarm threshold - matches the $20 AWS Budget from PLAN.md §4 | `number` | `20` | no |
| <a name="input_canary_runtime_version"></a> [canary\_runtime\_version](#input\_canary\_runtime\_version) | Synthetics canary Node.js/Puppeteer runtime version | `string` | `"syn-nodejs-puppeteer-9.1"` | no |
| <a name="input_canary_schedule_expression"></a> [canary\_schedule\_expression](#input\_canary\_schedule\_expression) | How often the Synthetics canary runs | `string` | `"rate(5 minutes)"` | no |
| <a name="input_db_instance_id"></a> [db\_instance\_id](#input\_db\_instance\_id) | RDS DBInstanceIdentifier (module.database.instance\_id) | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, prod, or test), used in resource naming/tags | `string` | n/a | yes |
| <a name="input_rds_max_connections_threshold"></a> [rds\_max\_connections\_threshold](#input\_rds\_max\_connections\_threshold) | Absolute DatabaseConnections count alarm threshold. Derived from db.t4g.micro's default max\_connections (~112, from RDS's memory-based formula) - 80% of that is ~90 | `number` | `90` | no |
| <a name="input_redis_replication_group_id"></a> [redis\_replication\_group\_id](#input\_redis\_replication\_group\_id) | ElastiCache replication group ID (module.cache.replication\_group\_id) - node is single-cluster, so CacheClusterId = "<this>-001" | `string` | n/a | yes |
| <a name="input_target_group_arn_suffix"></a> [target\_group\_arn\_suffix](#input\_target\_group\_arn\_suffix) | Target group arn\_suffix (module.edge.blue\_target\_group\_arn\_suffix) - CloudWatch TargetGroup dimension | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_billing_sns_topic_arn"></a> [billing\_sns\_topic\_arn](#output\_billing\_sns\_topic\_arn) | Billing alarm's dedicated us-east-1 SNS topic ARN - CloudWatch alarms can't target a topic outside their own region |
| <a name="output_canary_name"></a> [canary\_name](#output\_canary\_name) | Synthetics canary name |
| <a name="output_composite_alarm_name"></a> [composite\_alarm\_name](#output\_composite\_alarm\_name) | The "service degraded" composite alarm name |
| <a name="output_golden_signals_dashboard_name"></a> [golden\_signals\_dashboard\_name](#output\_golden\_signals\_dashboard\_name) | Four Golden Signals dashboard name |
| <a name="output_slo_dashboard_name"></a> [slo\_dashboard\_name](#output\_slo\_dashboard\_name) | SLO dashboard name |
| <a name="output_sns_topic_arn"></a> [sns\_topic\_arn](#output\_sns\_topic\_arn) | Alerts SNS topic ARN - every regional alarm and the composite alarm publish here (the billing alarm uses its own us-east-1 topic - see billing\_sns\_topic\_arn) |
<!-- END_TF_DOCS -->
