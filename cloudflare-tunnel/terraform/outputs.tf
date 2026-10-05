output "dns_record_ids" {
  value       = { for h, r in cloudflare_dns_record.this : h => r.id }
  description = "Map of hostname -> Cloudflare DNS record id. These are the ids the import procedure needs."
}

output "hostnames" {
  value       = sort(tolist(local.hostnames))
  description = "Distinct hostnames routed through the tunnel, one CNAME each."
}

output "tunnel_id" {
  value       = var.tunnel_id
  description = "Id of the tunnel this component configures."
}

output "access_application_ids" {
  value       = { for h, a in cloudflare_zero_trust_access_application.this : h => a.id }
  description = "Map of hostname -> Access application id, for the hostnames whose route has an access block. Empty when no route is protected."
}

output "access_aud_tags" {
  value       = { for h, a in cloudflare_zero_trust_access_application.this : h => a.aud }
  description = "Map of hostname -> Access application audience tag, the value cloudflared checks in the Access JWT. Empty when no route is protected."
}
