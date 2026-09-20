# edge

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
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.63.0 |
| <a name="provider_aws.use1"></a> [aws.use1](#provider\_aws.use1) | 6.63.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudfront_distribution.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution) | resource |
| [aws_cloudfront_origin_access_control.images](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control) | resource |
| [aws_cloudfront_response_headers_policy.security_headers](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_response_headers_policy) | resource |
| [aws_lb.app](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.http](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener_rule.from_cloudfront](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.blue](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group.green](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_s3_bucket.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_policy.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_policy.images](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.alb_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_security_group.alb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_wafv2_web_acl.cloudfront](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl) | resource |
| [random_id.alb_logs_bucket_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |
| [random_password.origin_secret](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [aws_ec2_managed_prefix_list.cloudfront](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ec2_managed_prefix_list) | data source |
| [aws_elb_service_account.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/elb_service_account) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_app_port"></a> [app\_port](#input\_app\_port) | Port the app instances listen on | `number` | `8080` | no |
| <a name="input_blue_weight"></a> [blue\_weight](#input\_blue\_weight) | Percentage weight (0-100) of listener traffic sent to the blue target group - Terraform-driven blue/green shifting, ADR-017 | `number` | `100` | no |
| <a name="input_deregistration_delay_seconds"></a> [deregistration\_delay\_seconds](#input\_deregistration\_delay\_seconds) | Seconds the ALB keeps sending an unregistering instance's in-flight requests to it before dropping it - applies to both the blue and green target groups | `number` | `30` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, prod, or test), used in resource naming/tags | `string` | n/a | yes |
| <a name="input_green_weight"></a> [green\_weight](#input\_green\_weight) | Percentage weight (0-100) of listener traffic sent to the green target group - Terraform-driven blue/green shifting, ADR-017 | `number` | `0` | no |
| <a name="input_health_check_healthy_threshold"></a> [health\_check\_healthy\_threshold](#input\_health\_check\_healthy\_threshold) | Consecutive passing health checks before a target is marked healthy - applies to both target groups | `number` | `2` | no |
| <a name="input_health_check_interval_seconds"></a> [health\_check\_interval\_seconds](#input\_health\_check\_interval\_seconds) | Seconds between health checks of each target - applies to both the blue and green target groups | `number` | `10` | no |
| <a name="input_health_check_matcher"></a> [health\_check\_matcher](#input\_health\_check\_matcher) | HTTP status codes that count as a passing health check: a code (200), a list (200,204) or a range (200-299) - applies to both target groups | `string` | `"200"` | no |
| <a name="input_health_check_path"></a> [health\_check\_path](#input\_health\_check\_path) | Shallow health check path the app exposes | `string` | `"/healthz"` | no |
| <a name="input_health_check_timeout_seconds"></a> [health\_check\_timeout\_seconds](#input\_health\_check\_timeout\_seconds) | Seconds to wait for a health check response before counting it as failed - applies to both target groups | `number` | `5` | no |
| <a name="input_health_check_unhealthy_threshold"></a> [health\_check\_unhealthy\_threshold](#input\_health\_check\_unhealthy\_threshold) | Consecutive failing health checks before a target is marked unhealthy - applies to both target groups | `number` | `2` | no |
| <a name="input_images_bucket_arn"></a> [images\_bucket\_arn](#input\_images\_bucket\_arn) | S3 images bucket ARN (modules/storage) - used in the OAC bucket policy, M6 | `string` | n/a | yes |
| <a name="input_images_bucket_id"></a> [images\_bucket\_id](#input\_images\_bucket\_id) | S3 images bucket name (modules/storage) - the OAC bucket policy target, M6 | `string` | n/a | yes |
| <a name="input_images_bucket_regional_domain_name"></a> [images\_bucket\_regional\_domain\_name](#input\_images\_bucket\_regional\_domain\_name) | S3 images bucket regional domain name (modules/storage) - CloudFront's /images/* origin, M6 | `string` | n/a | yes |
| <a name="input_origin_secret_header_name"></a> [origin\_secret\_header\_name](#input\_origin\_secret\_header\_name) | Header name CloudFront injects and the ALB listener checks for - the real authorization boundary, ADR-014 | `string` | `"X-Origin-Verify"` | no |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | Public-tier subnet IDs (both AZs) the ALB is deployed into | `list(string)` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR block - scopes the ALB's egress to app instances instead of 0.0.0.0/0 | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID the ALB and its target groups live in | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alb_arn"></a> [alb\_arn](#output\_alb\_arn) | n/a |
| <a name="output_alb_arn_suffix"></a> [alb\_arn\_suffix](#output\_alb\_arn\_suffix) | Shortened ALB identifier CloudWatch metrics key on (not the full ARN - AWS/ApplicationELB dimension quirk) |
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | Public DNS name of the ALB - should fail when curled directly (M4 DoD) |
| <a name="output_alb_security_group_id"></a> [alb\_security\_group\_id](#output\_alb\_security\_group\_id) | n/a |
| <a name="output_blue_target_group_arn"></a> [blue\_target\_group\_arn](#output\_blue\_target\_group\_arn) | n/a |
| <a name="output_blue_target_group_arn_suffix"></a> [blue\_target\_group\_arn\_suffix](#output\_blue\_target\_group\_arn\_suffix) | Shortened target-group identifier for the CloudWatch TargetGroup dimension |
| <a name="output_cloudfront_domain_name"></a> [cloudfront\_domain\_name](#output\_cloudfront\_domain\_name) | Public HTTPS entry point (M4 DoD: this works, the ALB DNS name directly does not) |
| <a name="output_green_target_group_arn"></a> [green\_target\_group\_arn](#output\_green\_target\_group\_arn) | Unused until M8's blue/green cutover |
| <a name="output_origin_secret_header_name"></a> [origin\_secret\_header\_name](#output\_origin\_secret\_header\_name) | n/a |
| <a name="output_origin_secret_header_value"></a> [origin\_secret\_header\_value](#output\_origin\_secret\_header\_value) | n/a |
| <a name="output_waf_web_acl_arn"></a> [waf\_web\_acl\_arn](#output\_waf\_web\_acl\_arn) | n/a |
<!-- END_TF_DOCS -->
