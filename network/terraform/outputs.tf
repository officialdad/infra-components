output "network_name" {
  value       = module.network.network_name
  description = "The VPC network name."
}

output "network_self_link" {
  value       = module.network.network_self_link
  description = "Network self link (pass to compute-engine.network)."
}

output "subnetwork_name" {
  value       = module.network.subnets_names[0]
  description = "The regional subnetwork name."
}

output "subnetwork_self_link" {
  value       = module.network.subnets_self_links[0]
  description = "Subnetwork self link (pass to compute-engine.subnetwork)."
}

output "region" {
  value       = var.global.deploy_region
  description = "Region the subnetwork lives in."
}

output "ssh_tag" {
  value       = local.ssh_tag
  description = "Network tag that grants IAP SSH. Pass into a VM's network_tags to let it accept SSH (e.g. network_tags = [module.network.ssh_tag])."
}
