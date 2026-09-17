output "vpc_id" {
  value = module.network.vpc_id
}

output "subnet_ids" {
  value = module.network.subnet_ids
}

output "alb_dns_name" {
  value = module.edge.alb_dns_name
}

output "cloudfront_domain_name" {
  value = module.edge.cloudfront_domain_name
}

output "images_bucket_name" {
  value = module.storage.images_bucket_id
}

output "redis_primary_endpoint" {
  value = module.cache.redis_primary_endpoint
}

output "golden_signals_dashboard_name" {
  value = module.observability.golden_signals_dashboard_name
}

output "slo_dashboard_name" {
  value = module.observability.slo_dashboard_name
}

output "alerts_sns_topic_arn" {
  value = module.observability.sns_topic_arn
}

output "asg_name" {
  value = module.compute.asg_name
}

output "launch_template_id" {
  value = module.compute.launch_template_id
}

output "artifact_key" {
  value = module.compute.artifact_key
}

output "artifacts_bucket_name" {
  value = module.storage.artifacts_bucket_name
}

output "origin_secret_header_name" {
  value = module.edge.origin_secret_header_name
}

output "origin_secret_header_value" {
  value     = module.edge.origin_secret_header_value
  sensitive = true
}
