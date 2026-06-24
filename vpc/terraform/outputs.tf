output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "The VPC id (pass to ec2.vpc_id)."
}

output "private_subnet_ids" {
  value       = module.vpc.private_subnets
  description = "Private subnet ids (pass ec2.subnet_id = private_subnet_ids[0])."
}

output "public_subnet_ids" {
  value       = module.vpc.public_subnets
  description = "Public subnet ids."
}

output "region" {
  value       = var.global.deploy_region
  description = "Region the VPC lives in."
}
