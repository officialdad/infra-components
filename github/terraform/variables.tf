variable "github_owner" {
  type        = string
  description = "The GitHub organization (or user) the provider operates on."
  default     = "officialdad"
}

variable "repositories" {
  type = map(object({
    description    = optional(string, "")
    visibility     = optional(string, "private")
    topics         = optional(list(string), [])
    default_branch = optional(string, "main")
    has_issues     = optional(bool, true)
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
