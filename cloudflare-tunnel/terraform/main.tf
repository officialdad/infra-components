# Puts an existing Cloudflare tunnel's ingress routes and their DNS records under Terraform.
# Two resources: the tunnel's remotely-managed config, and one proxied CNAME per hostname.
#
# Auth: the provider reads CLOUDFLARE_API_TOKEN from the environment. No secret is stored in this
# module or committed to git.
#
# Deliberately NOT here: cloudflare_zero_trust_tunnel_cloudflared (the tunnel resource). It carries
# tunnel_secret, which would be written to state in plaintext. The tunnel and its token are created
# by hand; the token lives in AWS SSM as a SecureString. Only the (non-secret) tunnel id comes in.

provider "cloudflare" {}

locals {
  # The last ingress rule must be hostname-less or Cloudflare rejects the whole config. Appended
  # here so callers never have to remember it.
  ingress = concat(
    [for r in var.routes : {
      hostname = r.hostname
      service  = r.service
      path     = r.path
    }],
    [{ service = "http_status:404" }]
  )

  # One CNAME per DISTINCT hostname — two path-scoped rules on one hostname share a single record.
  hostnames = toset([for r in var.routes : r.hostname])
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "this" {
  account_id = var.account_id
  tunnel_id  = var.tunnel_id

  config = {
    ingress = local.ingress
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
}
