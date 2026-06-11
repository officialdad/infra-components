variable "global" {
  type = object({
    environment_name = string
    deploy_region    = string
    tags             = map(string)
  })
  description = "Environment-wide context injected by the environments repo (name, region, tags)."
}

variable "project_id" {
  type        = string
  description = "GCP project the VM is created in."
}

variable "network" {
  type        = string
  description = "Network self link or name (from vpc.network_self_link)."
}

variable "subnetwork" {
  type        = string
  description = "Subnetwork self link or name (from vpc.subnetwork_self_link)."
}

variable "zone" {
  type        = string
  description = "Zone for the VM. Empty string -> \"<deploy_region>-a\"."
  default     = ""
}

variable "machine_type" {
  type        = string
  description = "Machine type."
  default     = "e2-micro"
}

variable "boot_image" {
  type        = string
  description = "Boot image as project/family or a full self link."
  default     = "debian-cloud/debian-12"
}

variable "boot_disk_size_gb" {
  type        = number
  description = "Boot disk size in GB."
  default     = 20
}

variable "startup_script" {
  type        = string
  description = "First-boot script (userdata) run via metadata_startup_script. \"\" = no bootstrap."
  default     = ""
}

variable "assign_public_ip" {
  type        = bool
  description = "Attach an ephemeral external IP. Leave false for the IAP-only model."
  default     = false
}

variable "access_members" {
  type        = list(string)
  description = "IAM principals granted OS Login + IAP tunnel access (e.g. user:me@x.com)."
  default     = []
}

variable "network_tags" {
  type        = list(string)
  description = "Network tags applied to the VM. Each tag opts the VM into the VPC firewall rules that target it (e.g. [module.vpc.ssh_tag] to allow IAP SSH). Empty = no tag-scoped inbound."
  default     = []
}
