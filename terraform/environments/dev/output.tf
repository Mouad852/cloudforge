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
