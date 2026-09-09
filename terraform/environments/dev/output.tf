output "vpc_id" {
  value = module.network.vpc_id
}

output "subnet_ids" {
  value = module.network.subnet_ids
}


output "alb_dns_name" {
  value = module.edge.alb_dns_name
}
