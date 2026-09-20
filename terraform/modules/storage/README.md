# storage

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
| <a name="provider_random"></a> [random](#provider\_random) | 3.9.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_s3_bucket.artifacts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket.images](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.artifacts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_policy.artifacts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.artifacts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_public_access_block.images](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.artifacts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.images](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.artifacts](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_s3_bucket_versioning.images](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [random_id.bucket_suffix](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/id) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_abort_incomplete_multipart_days"></a> [abort\_incomplete\_multipart\_days](#input\_abort\_incomplete\_multipart\_days) | Days after which an unfinished multipart upload to the artifacts bucket is aborted, so abandoned parts stop costing storage | `number` | `7` | no |
| <a name="input_artifact_version_retention_days"></a> [artifact\_version\_retention\_days](#input\_artifact\_version\_retention\_days) | Days a superseded (noncurrent) version of a deploy artifact is kept before it expires - the artifacts bucket is versioned, so old binaries pile up otherwise | `number` | `90` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, prod, or test), used in resource naming/tags | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_artifacts_bucket_arn"></a> [artifacts\_bucket\_arn](#output\_artifacts\_bucket\_arn) | ARN of the deploy-artifacts bucket |
| <a name="output_artifacts_bucket_name"></a> [artifacts\_bucket\_name](#output\_artifacts\_bucket\_name) | Name of the deploy-artifacts bucket |
| <a name="output_images_bucket_arn"></a> [images\_bucket\_arn](#output\_images\_bucket\_arn) | ARN of the CDN images bucket (M6) |
| <a name="output_images_bucket_id"></a> [images\_bucket\_id](#output\_images\_bucket\_id) | Name/ID of the CDN images bucket (M6) |
| <a name="output_images_bucket_regional_domain_name"></a> [images\_bucket\_regional\_domain\_name](#output\_images\_bucket\_regional\_domain\_name) | Regional domain name of the images bucket - CloudFront's OAC origin (M6) |
<!-- END_TF_DOCS -->
