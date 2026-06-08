output "repository_names" {
  value       = { for k, r in github_repository.this : k => r.full_name }
  description = "Map of repository key -> full name (owner/repo)."
}

output "repository_urls" {
  value       = { for k, r in github_repository.this : k => r.html_url }
  description = "Map of repository key -> HTML URL."
}

output "team_grants" {
  value       = { for k, g in github_team_repository.default : k => "${var.default_team}:${g.permission}" }
  description = "Map of repository key -> \"team:permission\" granted by the default team."
}
