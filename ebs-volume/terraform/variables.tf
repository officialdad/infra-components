variable "global" {
  type = object({
    environment_name = string
    deploy_region    = string
    tags             = map(string)
  })
  description = "Environment-wide context injected by the environments repo (name, region, tags)."
}

variable "volumes" {
  type = map(object({
    availability_zone = string
    size_gb           = optional(number, 20)
    type              = optional(string, "gp3")
    iops              = optional(number)
    throughput        = optional(number)
    final_snapshot    = optional(bool, false)
  }))
  description = "EBS data volumes keyed by short name; each entry overrides only what it needs. Name tag = \"<env>-<key>\" — the value the consuming instance self-attaches by. availability_zone is required and AZ-locked: it must match the AZ of the subnet the instance launches into. encrypted is always true. final_snapshot defaults false (opt in for a recovery snapshot on destroy); the env owns hard destroy-protection via Terragrunt prevent_destroy."
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.volumes) : can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$|^[a-z]$", k))])
    error_message = "Each volumes key must be: lowercase letter first, then lowercase/digits/hyphens, no trailing hyphen, ≤63 chars."
  }
}
