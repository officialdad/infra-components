variable "github_owner" {
  type        = string
  description = "The GitHub organization (or user) the provider operates on."
  default     = "officialdad"
}

variable "default_team" {
  type        = string
  description = "Team slug granted access to every managed repo by default. Empty string disables the default grant. The team must already exist in the org."
  default     = "engineering"
}

variable "default_team_permission" {
  type        = string
  description = "Permission the default team receives on each repo."
  default     = "push"

  validation {
    condition     = contains(["pull", "triage", "push", "maintain", "admin"], var.default_team_permission)
    error_message = "default_team_permission must be one of: pull, triage, push, maintain, admin."
  }
}

variable "repositories" {
  type = map(object({
    description            = optional(string, "")
    visibility             = optional(string, "private")
    topics                 = optional(list(string), [])
    default_branch         = optional(string, "main")
    has_issues             = optional(bool, true)
    delete_branch_on_merge = optional(bool, true)
    branch_protection = optional(object({
      required_approving_review_count = optional(number, 1)
      required_status_checks          = optional(list(string), [])
      enforce_admins                  = optional(bool, false)
    }))
  }))
  description = "Repositories to manage, keyed by repo name. Each value configures one repo; omit branch_protection to leave the default branch unprotected."
  default     = {}

  validation {
    condition = alltrue([
      for cfg in values(var.repositories) :
      contains(["private", "public", "internal"], cfg.visibility)
    ])
    error_message = "Each repository visibility must be one of: private, public, internal."
  }
}
