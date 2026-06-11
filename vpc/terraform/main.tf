provider "google" {
  project = var.project_id
  region  = var.global.deploy_region
}

locals {
  name_prefix = "${var.global.environment_name}-vpc"
  ssh_tag     = "${var.global.environment_name}-ssh"
}

# Custom-mode VPC: we declare the one subnet ourselves (no auto subnet in every region).
resource "google_compute_network" "this" {
  name                    = local.name_prefix
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# One regional subnet. private_ip_google_access lets VMs reach Google APIs with no external IP.
resource "google_compute_subnetwork" "this" {
  name                     = "${local.name_prefix}-subnet"
  ip_cidr_range            = var.subnet_cidr
  region                   = var.global.deploy_region
  network                  = google_compute_network.this.id
  private_ip_google_access = true
}

# Cloud Router + NAT = outbound internet for private VMs (e.g. to apt-install Docker).
# Router is free; NAT bills ~$1/day while it exists — destroy it to stop idle charges.
resource "google_compute_router" "this" {
  count   = var.enable_cloud_nat ? 1 : 0
  name    = "${local.name_prefix}-router"
  region  = var.global.deploy_region
  network = google_compute_network.this.id
}

resource "google_compute_router_nat" "this" {
  count                              = var.enable_cloud_nat ? 1 : 0
  name                               = "${local.name_prefix}-nat"
  router                             = google_compute_router.this[0].name
  region                             = var.global.deploy_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Allow traffic between instances inside the VPC.
resource "google_compute_firewall" "allow_internal" {
  name    = "${local.name_prefix}-allow-internal"
  network = google_compute_network.this.id

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  source_ranges = [var.subnet_cidr]
}

# Allow SSH only from Google's IAP forwarders — no public SSH exposure.
resource "google_compute_firewall" "allow_iap_ssh" {
  count   = var.enable_iap_ssh ? 1 : 0
  name    = "${local.name_prefix}-allow-iap-ssh"
  network = google_compute_network.this.id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"] # IAP's published TCP-forwarding range.
}
