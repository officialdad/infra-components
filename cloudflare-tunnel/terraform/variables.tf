variable "account_id" {
  type        = string
  description = "Cloudflare account id that owns the tunnel."
}

variable "zone_id" {
  type        = string
  description = "Cloudflare zone id the route hostnames live in. Every hostname in routes must belong to this zone."
}

variable "tunnel_id" {
  type        = string
  description = "Id of the already-created tunnel this component configures. Not a secret — the tunnel and its token are created out-of-band (see README)."
}

variable "routes" {
  type = list(object({
    hostname = string
    service  = string
    path     = optional(string)
    access = optional(object({
      emails        = optional(list(string), [])
      email_domains = optional(list(string), [])
      policy_ids    = optional(list(string), [])
      allowed_idps  = optional(list(string))
    }))
  }))
  description = "Ingress rules for the tunnel, in match order. Cloudflare takes the first match, so a path-scoped rule must come before the unscoped rule for the same hostname, or the unscoped rule swallows every request. The path field is a regex evaluated by cloudflared and is passed through untouched. The trailing catch-all rule is appended by the module — do not include it here. The optional access object puts the route's hostname behind Cloudflare Access: emails and email_domains become one allow policy, policy_ids are existing policies attached alongside it, and allowed_idps (identity provider ids) limits the login methods, defaulting to every method on the account when null. Every route on one hostname must carry the same access object, because Access protects a hostname, not a path. Needs access_team_name."

  validation {
    condition     = length(var.routes) > 0
    error_message = "routes must contain at least one rule; an empty list would publish a catch-all-only config and drop every existing route."
  }

  validation {
    condition     = alltrue([for r in var.routes : r.hostname != "" && r.service != ""])
    error_message = "Each route needs a non-empty hostname and service."
  }

  validation {
    condition = alltrue([
      for h in distinct([for r in var.routes : r.hostname]) :
      length(distinct([for r in var.routes : jsonencode(r.access) if r.hostname == h])) == 1
    ])
    error_message = "Every route on the same hostname must carry the same access object (or none). Access protects a whole hostname, so a mix would leave one path open."
  }

  validation {
    condition = alltrue([
      for r in var.routes :
      length(r.access.emails) + length(r.access.email_domains) + length(r.access.policy_ids) > 0
      if r.access != null
    ])
    error_message = "An access block must name at least one of emails, email_domains or policy_ids. An empty allow policy admits nobody, and the module never builds an everyone rule."
  }

  validation {
    condition = alltrue([
      for r in var.routes :
      alltrue([for v in concat(r.access.emails, r.access.email_domains, r.access.policy_ids) : trimspace(v) != "" && !strcontains(v, "*")])
      if r.access != null
    ])
    error_message = "access emails, email_domains and policy_ids must be non-empty and free of wildcards. A wildcard would turn the allow list into an everyone rule."
  }

  validation {
    condition = alltrue([
      for r in var.routes :
      r.access.allowed_idps == null ? true : (length(r.access.allowed_idps) > 0 && alltrue([for i in r.access.allowed_idps : trimspace(i) != ""]))
      if r.access != null
    ])
    error_message = "access allowed_idps must be null (keep the account's login methods) or a non-empty list of non-empty identity provider ids. An empty list would lock everyone out."
  }
}

variable "access_team_name" {
  type        = string
  default     = null
  description = "Zero Trust team name, the subdomain of <team>.cloudflareaccess.com. cloudflared uses it to check the Access JWT on every protected route, so it is required as soon as any route has an access block. A wrong value makes cloudflared reject every request."
}
