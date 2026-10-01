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
    snapshot = optional(object({
      times        = optional(list(string), ["18:00"])
      retain_count = optional(number, 7)
    }))
  }))
  description = "EBS data volumes keyed by short name; each entry overrides only what it needs. Name tag = \"<env>-<key>\" — the value the consuming instance self-attaches by. availability_zone is required and AZ-locked: it must match the AZ of the subnet the instance launches into. encrypted is always true. final_snapshot defaults false (opt in for a recovery snapshot on destroy); the env owns hard destroy-protection via Terragrunt prevent_destroy. snapshot defaults null (no backups); set it (even as {}) to tag the volume Backup = \"<env>-<key>\" and create a daily DLM snapshot policy on that tag. snapshot.times is one UTC HH:MM (default 18:00 = 02:00 Asia/Kuala_Lumpur), snapshot.retain_count is how many snapshots to keep (default 7)."
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.volumes) : can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$|^[a-z]$", k))])
    error_message = "Each volumes key must be: lowercase letter first, then lowercase/digits/hyphens, no trailing hyphen, ≤63 chars."
  }

  validation {
    condition = alltrue([
      for v in values(var.volumes) : v.snapshot == null ? true : (
        length(v.snapshot.times) == 1 && alltrue([for t in v.snapshot.times : can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", t))])
      )
    ])
    error_message = "snapshot.times must hold exactly one UTC time in 24-hour HH:MM form (DLM allows one start time per schedule)."
  }

  validation {
    condition = alltrue([
      for v in values(var.volumes) : v.snapshot == null ? true : (
        v.snapshot.retain_count >= 1 && v.snapshot.retain_count <= 1000 && v.snapshot.retain_count == floor(v.snapshot.retain_count)
      )
    ])
    error_message = "snapshot.retain_count must be a whole number between 1 and 1000."
  }
}
