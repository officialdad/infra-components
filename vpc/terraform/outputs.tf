output "network_name" {
  value       = google_compute_network.this.name
  description = "The VPC network name."
}

output "network_self_link" {
  value       = google_compute_network.this.self_link
  description = "Network self link (pass to compute-engine.network)."
}

output "subnetwork_name" {
  value       = google_compute_subnetwork.this.name
  description = "The regional subnetwork name."
}

output "subnetwork_self_link" {
  value       = google_compute_subnetwork.this.self_link
  description = "Subnetwork self link (pass to compute-engine.subnetwork)."
}

output "region" {
  value       = google_compute_subnetwork.this.region
  description = "Region the subnetwork lives in."
}

output "ssh_tag" {
  value       = local.ssh_tag
  description = "Network tag that grants IAP SSH. Pass into a VM's network_tags to let it accept SSH (e.g. network_tags = [module.vpc.ssh_tag])."
}
