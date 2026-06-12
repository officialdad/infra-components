output "instance_name" {
  value       = google_compute_instance.this.name
  description = "The VM name."
}

output "instance_id" {
  value       = google_compute_instance.this.instance_id
  description = "The instance ID."
}

output "internal_ip" {
  value       = google_compute_instance.this.network_interface[0].network_ip
  description = "The VM's internal IP."
}

output "zone" {
  value       = google_compute_instance.this.zone
  description = "The zone the VM runs in."
}

output "ssh_command" {
  value       = "gcloud compute ssh ${google_compute_instance.this.name} --zone ${google_compute_instance.this.zone} --project ${var.project_id} --tunnel-through-iap"
  description = "Ready-to-run IAP SSH command."
}
