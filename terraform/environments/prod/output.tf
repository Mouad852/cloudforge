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
