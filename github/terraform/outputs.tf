output "repository_names" {
  value       = { for k, r in github_repository.this : k => r.full_name }
  description = "Map of repository key -> full name (owner/repo)."
}

output "repository_urls" {
  value       = { for k, r in github_repository.this : k => r.html_url }
  description = "Map of repository key -> HTML URL."
}
