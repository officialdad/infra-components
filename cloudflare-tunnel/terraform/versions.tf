terraform {
  required_version = ">= 1.5.7"

  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
      # v5 is the floor, not a preference: it is the version that renamed these resources to
      # cloudflare_zero_trust_tunnel_cloudflared_config / cloudflare_dns_record.
      version = "~> 5.0"
    }
  }
}
