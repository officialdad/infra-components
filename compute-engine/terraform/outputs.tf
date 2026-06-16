output "instances" {
  value = {
    for k, vm in google_compute_instance.this : k => {
      name        = vm.name
      instance_id = vm.instance_id
      internal_ip = vm.network_interface[0].network_ip
      zone        = vm.zone
      ssh_command = "gcloud compute ssh ${vm.name} --zone ${vm.zone} --project ${var.project_id} --tunnel-through-iap"
    }
  }
  description = "Per-instance details keyed by instance key: name, instance_id, internal_ip, zone, and a ready-to-run IAP ssh_command."
}
