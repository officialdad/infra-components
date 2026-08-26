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
