provider "google" {
  project = var.project_id
  region  = var.global.deploy_region
}

locals {
  # GCP labels are constrained (lowercase, keys/values in [a-z0-9_-], keys start with a letter,
  # <= 63 chars), unlike free-form AWS tags. Sanitize var.global.tags — replace disallowed chars
  # with "_" and lowercase — so the env's tag contract is honored here too instead of being dropped.
  # GCP *networking* resources can't be labeled at all (see the network component).
  sanitized_tags = {
    for k, v in var.global.tags :
    lower(replace(k, "/[^a-zA-Z0-9_-]/", "_")) => lower(replace(v, "/[^a-zA-Z0-9_-]/", "_"))
  }

  # Always-on env/managed_by labels win over any same-named global tag.
  labels = merge(local.sanitized_tags, {
    environment = lower(var.global.environment_name)
    managed_by  = "terraform"
  })

  # member x instance -> one stable key per pair, so for_each never reindexes
  # when a VM or a member is added/removed.
  vm_access = {
    for pair in setproduct(keys(var.instances), var.access_members) :
    "${pair[0]}:${pair[1]}" => { instance = pair[0], member = pair[1] }
  }
}

resource "google_compute_instance" "this" {
  for_each = var.instances

  name         = "${var.global.environment_name}-${each.key}"
  machine_type = each.value.machine_type
  zone         = each.value.zone != "" ? each.value.zone : "${var.global.deploy_region}-a"
  labels       = local.labels
  tags         = each.value.network_tags

  # Destroy-friendly: no accidental lock, and changing machine_type stops the VM
  # instead of forcing a full recreate.
  deletion_protection       = false
  allow_stopping_for_update = true

  boot_disk {
    auto_delete = true # disk is deleted with the VM -> no orphaned disk cost
    initialize_params {
      image = each.value.boot_image
      size  = each.value.boot_disk_size_gb
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork

    # Emitting access_config = an external IP. Omit it (default) = no public IP.
    dynamic "access_config" {
      for_each = each.value.assign_public_ip ? [1] : []
      content {}
    }
  }

  metadata = {
    enable-oslogin = "TRUE" # SSH access governed by IAM, not metadata keys.
  }

  # Caller-supplied userdata; null (unset) when empty.
  metadata_startup_script = each.value.startup_script != "" ? each.value.startup_script : null
}

# OS Login: who may SSH in (identity-based). Every member on every VM.
resource "google_compute_instance_iam_member" "os_login" {
  for_each      = local.vm_access
  project       = var.project_id
  zone          = google_compute_instance.this[each.value.instance].zone
  instance_name = google_compute_instance.this[each.value.instance].name
  role          = "roles/compute.osLogin"
  member        = each.value.member
}

# IAP: who may open the tunnel that reaches each (private) VM's SSH port.
resource "google_iap_tunnel_instance_iam_member" "tunnel" {
  for_each = local.vm_access
  project  = var.project_id
  zone     = google_compute_instance.this[each.value.instance].zone
  instance = google_compute_instance.this[each.value.instance].name
  role     = "roles/iap.tunnelResourceAccessor"
  member   = each.value.member
}
