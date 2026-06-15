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
  description = "GCP project the VMs are created in. Defaults to the dev project; override per environment."
  default     = "master-dreamer-498805-d6"
}

variable "network" {
  type        = string
  description = "Network self link or name (from network.network_self_link). Shared by all instances."
}

variable "subnetwork" {
  type        = string
  description = "Subnetwork self link or name (from network.subnetwork_self_link). Shared by all instances."
}

variable "access_members" {
  type        = list(string)
  description = "IAM principals granted OS Login + IAP tunnel access on EVERY VM. Defaults to the org's two engineers; override to change who can SSH."
  default     = ["user:sydazm06@gmail.com", "user:ariff.azman@doubleadigital.my"]
}

variable "instances" {
  type = map(object({
    machine_type      = optional(string, "e2-micro")
    boot_image        = optional(string, "debian-cloud/debian-12")
    boot_disk_size_gb = optional(number, 20)
    zone              = optional(string, "")       # "" -> "<deploy_region>-a"
    assign_public_ip  = optional(bool, false)      # false -> IAP-only, no public IP
    startup_script    = optional(string, "")       # "" -> no bootstrap
    network_tags      = optional(list(string), []) # [] -> no firewall tag opt-in
  }))
  description = "VMs to create, keyed by short name. Each entry overrides only the fields it needs; the rest take module defaults. VM name = \"<env>-compute-engine-<key>\"."
  default     = {}
}
