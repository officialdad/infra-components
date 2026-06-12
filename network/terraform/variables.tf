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
  description = "GCP project the network is created in."
}

variable "subnet_cidr" {
  type        = string
  description = "Primary IPv4 range of the regional subnetwork."
  default     = "10.0.0.0/16"
}

variable "enable_cloud_nat" {
  type        = bool
  description = "Create Cloud Router + NAT so instances with no external IP get egress."
  default     = true
}

variable "enable_iap_ssh" {
  type        = bool
  description = "Allow SSH (tcp:22) from Google's IAP range so --tunnel-through-iap works."
  default     = true
}
