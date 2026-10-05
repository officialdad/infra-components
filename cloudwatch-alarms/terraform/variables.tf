variable "global" {
  type = object({
    environment_name = string
    deploy_region    = string
    tags             = map(string)
  })
  description = "Environment-wide context injected by the environments repos (name, region, tags)."
}

variable "alarm_emails" {
  type        = list(string)
  description = "Email addresses subscribed to the alarm topic. Required: an alarm nobody hears is worse than a failed plan. Each address must confirm its subscription from the email AWS sends before it receives anything."

  validation {
    condition     = length(var.alarm_emails) > 0 && alltrue([for e in var.alarm_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "alarm_emails must hold at least one address, and each must look like name@domain.tld."
  }
}

variable "instances" {
  type = map(object({
    instance_id = string
  }))
  default     = {}
  description = "EC2 instances to alarm on, keyed by short name (the ec2 component's instances output fits as is - extra attributes are ignored). Each gets a StatusCheckFailed_System alarm that also runs the ec2:recover action, and a StatusCheckFailed_Instance alarm. ec2:recover cannot recover instances with instance-store volumes."

  validation {
    condition     = alltrue([for k in keys(var.instances) : can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$|^[a-z]$", k))])
    error_message = "Each instances key must be: lowercase letter first, then lowercase/digits/hyphens, no trailing hyphen, ≤63 chars."
  }
}

variable "disk_alarm" {
  type = object({
    namespace   = optional(string, "CWAgent")
    metric_name = optional(string, "disk_used_percent")
    threshold   = optional(number, 80)
    dimensions  = optional(map(string), {})
  })
  default     = null
  description = "Per-instance alarm on a custom disk-used-percent metric; null (default) creates none. The metric comes from the CloudWatch agent, which the consuming environment installs. InstanceId is always added to the dimensions; dimensions adds the rest (for example path, device, fstype), which must match the published metric exactly or the alarm never sees data. threshold is a percentage."

  validation {
    condition     = var.disk_alarm == null ? true : var.disk_alarm.threshold > 0 && var.disk_alarm.threshold <= 100
    error_message = "disk_alarm.threshold must be a percentage above 0 and at most 100."
  }

  validation {
    condition     = var.disk_alarm == null ? true : !contains(keys(var.disk_alarm.dimensions), "InstanceId")
    error_message = "disk_alarm.dimensions must not set InstanceId - the module adds it per instance."
  }
}

variable "backup_age_alarm" {
  type = object({
    namespace          = string
    metric_name        = string
    threshold          = number
    dimensions         = optional(map(string), {})
    period             = optional(number, 3600)
    treat_missing_data = optional(string, "breaching")
  })
  default     = null
  description = "One alarm on a custom backup-age metric that the consuming environment publishes; null (default) creates none. threshold uses the metric's own unit (for example seconds), so it has no default. dimensions are used verbatim. The publisher must emit at least one datapoint per period (seconds, default 3600). With treat_missing_data = breaching (default) a publisher that stops running raises the alarm, which is the failure this alarm exists to catch."

  validation {
    condition     = var.backup_age_alarm == null ? true : var.backup_age_alarm.threshold > 0
    error_message = "backup_age_alarm.threshold must be above 0."
  }

  validation {
    condition     = var.backup_age_alarm == null ? true : contains(["breaching", "notBreaching", "ignore", "missing"], var.backup_age_alarm.treat_missing_data)
    error_message = "backup_age_alarm.treat_missing_data must be one of breaching, notBreaching, ignore, missing."
  }

  validation {
    condition     = var.backup_age_alarm == null ? true : var.backup_age_alarm.period >= 60 && var.backup_age_alarm.period % 60 == 0
    error_message = "backup_age_alarm.period must be a multiple of 60 seconds."
  }
}
