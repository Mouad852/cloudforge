output "vpc_id" {
  description = "The VPC ID"
  value       = aws_vpc.main.id
}

output "subnet_ids" {
  description = "Map of subnet name to subnet ID"
  value       = { for k, v in aws_subnet.this : k => v.id }
}

output "public_route_table_id" {
  description = "The public route table ID"
  value       = aws_route_table.public.id
}

output "private_route_table_id" {
  description = "The private route table ID"
  value       = aws_route_table.private.id
}

output "nat_instance_public_ip" {
  description = "Public (Elastic) IP of the NAT instance"
  value       = aws_eip.nat.public_ip
}
