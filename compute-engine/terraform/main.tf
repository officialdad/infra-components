provider "google" {
  project = var.project_id
  region  = var.global.deploy_region
}

locals {
  name_prefix = "${var.global.environment_name}-compute-engine"

  # Default to zone "a" in the deploy region unless the caller pins one.
  zone = var.zone != "" ? var.zone : "${var.global.deploy_region}-a"

  # GCP labels must be lowercase; only this subset of the tags convention maps cleanly.
  labels = {
    environment = lower(var.global.environment_name)
    managed_by  = "terraform"
  }
}

resource "google_compute_instance" "this" {
  name         = local.name_prefix
  machine_type = var.machine_type
  zone         = local.zone
  labels       = local.labels
  tags         = var.network_tags

  # Destroy-friendly: no accidental lock, and changing machine_type stops the VM
  # instead of forcing a full recreate.
  deletion_protection       = false
  allow_stopping_for_update = true

  boot_disk {
    auto_delete = true # disk is deleted with the VM -> no orphaned disk cost
    initialize_params {
      image = var.boot_image
      size  = var.boot_disk_size_gb
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork

    # Emitting access_config = an external IP. Omit it (default) = no public IP.
    dynamic "access_config" {
      for_each = var.assign_public_ip ? [1] : []
      content {}
    }
  }

  metadata = {
    enable-oslogin = "TRUE" # SSH access governed by IAM, not metadata keys.
  }

  # Caller-supplied userdata; null (unset) when empty.
  metadata_startup_script = var.startup_script != "" ? var.startup_script : null
}

# OS Login: who may SSH in (identity-based).
resource "google_compute_instance_iam_member" "os_login" {
  for_each      = toset(var.access_members)
  project       = var.project_id
  zone          = local.zone
  instance_name = google_compute_instance.this.name
  role          = "roles/compute.osLogin"
  member        = each.value
}

# IAP: who may open the tunnel that reaches the (private) VM's SSH port.
resource "google_iap_tunnel_instance_iam_member" "tunnel" {
  for_each = toset(var.access_members)
  project  = var.project_id
  zone     = local.zone
  instance = google_compute_instance.this.name
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.value
}
