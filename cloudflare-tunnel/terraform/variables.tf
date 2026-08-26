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
  }))
  description = "Ingress rules for the tunnel, in match order. Cloudflare takes the first match, so a path-scoped rule must come before the unscoped rule for the same hostname, or the unscoped rule swallows every request. The path field is a regex evaluated by cloudflared and is passed through untouched. The trailing catch-all rule is appended by the module — do not include it here."

  validation {
    condition     = length(var.routes) > 0
    error_message = "routes must contain at least one rule; an empty list would publish a catch-all-only config and drop every existing route."
  }

  validation {
    condition     = alltrue([for r in var.routes : r.hostname != "" && r.service != ""])
    error_message = "Each route needs a non-empty hostname and service."
  }
}
