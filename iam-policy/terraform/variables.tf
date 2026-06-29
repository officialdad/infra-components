variable "global" {
  type = object({
    environment_name = string
    deploy_region    = string
    tags             = map(string)
  })
  description = "Environment-wide context injected by the environments repo (name, region, tags)."
}

variable "policies" {
  type = map(object({
    policy_json = string
    description = optional(string, "")
  }))
  description = "IAM managed policies keyed by short name; each entry's policy_json is the full IAM policy document (the consumer composes it). Policy name = \"<environment_name>-<key>\". Feed policy_arns[<key>] into a consumer role (e.g. ec2 iam_role_policy_arns)."
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.policies) : can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$|^[a-z]$", k))])
    error_message = "Each policies key must be: lowercase letter first, then lowercase/digits/hyphens, no trailing hyphen, ≤63 chars."
  }

  validation {
    condition     = alltrue([for p in values(var.policies) : can(jsondecode(p.policy_json))])
    error_message = "Each policies entry's policy_json must be a valid JSON document (use jsonencode(...))."
  }
}
