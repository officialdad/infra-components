provider "google" {
  project = var.project_id
  region  = var.global.deploy_region
}

# The network module declares google-beta; configure it so its beta-backed
# paths have a project/region even though we write no beta resources ourselves.
provider "google-beta" {
  project = var.project_id
  region  = var.global.deploy_region
}

locals {
  name_prefix = "${var.global.environment_name}-network"
  ssh_tag     = "${var.global.environment_name}-ssh"
}

# Network + subnet + firewall via the verified CFT network module.
# Firewall baseline is expressed as ingress_rules (no hand-written
# google_compute_firewall); the IAP-SSH rule is scoped to ssh_tag.
module "network" {
  source  = "terraform-google-modules/network/google"
  version = "~> 18.0"

  project_id   = var.project_id
  network_name = local.name_prefix
  routing_mode = "REGIONAL"

  subnets = [{
    subnet_name           = "${local.name_prefix}-subnet"
    subnet_ip             = var.subnet_cidr
    subnet_region         = var.global.deploy_region
    subnet_private_access = "true"
  }]

  ingress_rules = concat(
    [{
      name          = "${local.name_prefix}-allow-internal"
      source_ranges = [var.subnet_cidr]
      target_tags   = null
      allow = [
        { protocol = "tcp", ports = [] },
        { protocol = "udp", ports = [] },
        { protocol = "icmp", ports = [] },
      ]
    }],
    var.enable_iap_ssh ? [{
      name          = "${local.name_prefix}-allow-iap-ssh"
      source_ranges = ["35.235.240.0/20"] # IArange.
      target_tags   = [local.ssh_tag]
      allow = [
        { protocol = "tcp", ports = ["22"] },
      ]
    }] : []
  )
}

# Cloud Router + NAT = outbound internet for private VMs (e.g. to apt-install Docker).
# Router is free; NAT bills while it exists — set enable_cloud_nat=false to stop idle charges.
module "cloud_router" {
  source  = "terraform-google-modules/cloud-router/google"
  version = "~> 9.0"
  count   = var.enable_cloud_nat ? 1 : 0

  name       = "${local.name_prefix}-router"
  project_id = var.project_id
  region     = var.global.deploy_region
  network    = module.network.network_name

  nats = [{
    name                               = "${local.name_prefix}-nat"
    source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
    nat_ip_allocate_option             = "AUTO_ONLY"
  }]
}
