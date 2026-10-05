variable "global" {
  type = object({
    environment_name = string
    deploy_region    = string
    tags             = map(string)
  })
  description = "Environment-wide context injected by the environments repo (name, region, tags)."
}

variable "github_org" {
  type        = string
  description = "GitHub org/user that owns the CI repo allowed to assume the role."
  default     = "officialdad"
}

variable "github_repo" {
  type        = string
  description = "GitHub repo (within github_org) whose Actions workflows assume the role."
  default     = "infra-environments-dev"
}

variable "allowed_subjects" {
  type        = list(string)
  description = "OIDC `sub` claims allowed to assume the role (StringLike). Empty = the recommended ref/event-scoped default: the repo's main branch (apply) + pull_request events (plan). Override to tighten or loosen, e.g. [\"repo:org/repo:*\"] for any ref. Never use a bare org/* wildcard."
  default     = []
}

variable "role_name" {
  type        = string
  description = "Name of the IAM role CI assumes. Empty = \"<environment_name>-github-actions-ci\"."
  default     = ""
}

variable "create_oidc_provider" {
  type        = bool
  description = "Create the account-global GitHub OIDC provider. Set false if the account already federates GitHub (token.actions.githubusercontent.com) and pass existing_oidc_provider_arn instead."
  default     = true
}

variable "existing_oidc_provider_arn" {
  type        = string
  description = "ARN of a pre-existing GitHub OIDC provider. Used (and required) only when create_oidc_provider = false."
  default     = ""

  validation {
    condition     = var.create_oidc_provider || var.existing_oidc_provider_arn != ""
    error_message = "existing_oidc_provider_arn must be set when create_oidc_provider = false."
  }
}

variable "additional_policy_arns" {
  type        = list(string)
  description = "Extra managed policy ARNs to attach to the role, on top of the built-in least-privilege policy. Keep this empty unless a unit genuinely needs more than vpc+ec2 require."
  default     = []
}

variable "additional_regions" {
  type        = list(string)
  description = "Extra AWS regions the CI role may act on EC2 in, on top of global.deploy_region. For an environment whose components deploy to more than one region (e.g. dev's *_my units in ap-southeast-5). Empty = deploy_region only."
  default     = []

  validation {
    condition     = alltrue([for r in var.additional_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", r))])
    error_message = "Each additional_regions entry must be an AWS region code, e.g. \"ap-southeast-5\"."
  }
}
