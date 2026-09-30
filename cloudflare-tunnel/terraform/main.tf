# Puts an existing Cloudflare tunnel's ingress routes and their DNS records under Terraform.
# The tunnel's remotely-managed config, one proxied CNAME per hostname, and, for routes that carry
# an access block, the Access application and allow policy that protect the hostname.
#
# Auth: the provider reads CLOUDFLARE_API_TOKEN from the environment. No secret is stored in this
# module or committed to git.
#
# Deliberately NOT here: cloudflare_zero_trust_tunnel_cloudflared (the tunnel resource). It carries
# tunnel_secret, which would be written to state in plaintext. The tunnel and its token are created
# by hand; the token lives in AWS SSM as a SecureString. Only the (non-secret) tunnel id comes in.

provider "cloudflare" {}

locals {
  # Access protects a whole hostname, and the routes variable validates that every route on a
  # hostname carries the same access object. The "..." grouping therefore only ever collects
  # identical copies, and [0] picks one.
  access_by_hostname = {
    for h, accesses in { for r in var.routes : r.hostname => r.access... if r.access != null } : h => accesses[0]
  }

  # A policy is only built from emails and email domains. A route that passes only existing
  # policy_ids attaches those and creates none.
  access_policy_by_hostname = {
    for h, a in local.access_by_hostname : h => a if length(a.emails) + length(a.email_domains) > 0
  }

  # The last ingress rule must be hostname-less or Cloudflare rejects the whole config. Appended
  # here so callers never have to remember it.
  ingress = concat(
    [for r in var.routes : {
      hostname = r.hostname
      service  = r.service
      path     = r.path
      # null for an unprotected route, so it plans exactly as it did before access existed.
      origin_request = r.access == null ? null : {
        access = {
          required  = true
          team_name = var.access_team_name
          aud_tag   = [cloudflare_zero_trust_access_application.this[r.hostname].aud]
        }
      }
    }],
    [{ service = "http_status:404" }]
  )

  # One CNAME per DISTINCT hostname — two path-scoped rules on one hostname share a single record.
  hostnames = toset([for r in var.routes : r.hostname])
}

resource "cloudflare_zero_trust_access_policy" "this" {
  for_each = local.access_policy_by_hostname

  account_id = var.account_id
  name       = "${each.key}-allow"
  decision   = "allow"

  include = concat(
    [for e in each.value.emails : { email = { email = e } }],
    [for d in each.value.email_domains : { email_domain = { domain = d } }],
  )
}

resource "cloudflare_zero_trust_access_application" "this" {
  for_each = local.access_by_hostname

  account_id = var.account_id
  name       = each.key
  domain     = each.key
  type       = "self_hosted"

  # null keeps the account's login methods. The email allow list then gates the app alone.
  allowed_idps = each.value.allowed_idps == null ? null : toset(each.value.allowed_idps)

  # Cloudflare only accepts the redirect when exactly one identity provider is allowed.
  auto_redirect_to_identity = length(coalesce(each.value.allowed_idps, [])) == 1 ? true : null

  # The module-built policy is chosen from known inputs. Filtering on the planned policy object
  # makes the list length unknown at plan time, and the provider rejects an unknown policies list.
  policies = [
    for i, id in concat(
      contains(keys(local.access_policy_by_hostname), each.key) ? [cloudflare_zero_trust_access_policy.this[each.key].id] : [],
      each.value.policy_ids,
    ) : { id = id, precedence = i + 1 }
  ]
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.account_id
  tunnel_id  = var.tunnel_id

  config = {
    ingress = local.ingress
  }

  lifecycle {
    precondition {
      condition     = length(local.access_by_hostname) == 0 || var.access_team_name != null
      error_message = "access_team_name is required when any route has an access block. cloudflared needs it to check the Access JWT."
    }
  }
}

resource "cloudflare_dns_record" "this" {
  for_each = local.hostnames

  zone_id = var.zone_id
  name    = each.key
  type    = "CNAME"
  content = "${var.tunnel_id}.cfargotunnel.com"
  proxied = true

  # 1 means "automatic" and is the only value Cloudflare accepts on a proxied record.
  ttl = 1

  # No hostname may resolve before its Access application exists, or it is briefly reachable
  # unprotected.
  depends_on = [cloudflare_zero_trust_access_application.this]
}
