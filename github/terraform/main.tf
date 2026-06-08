# Manages GitHub repositories as code. One provider plus three resources fanned out over
# the `repositories` map, so adding a repo on the consumer side is a single map entry.
#
# Auth: the provider reads GITHUB_TOKEN from the environment (a PAT or GitHub App token).
# No secret is stored in this module or committed to git. This is the first component that
# needs a credential — it cannot run on the credential-free TG_BACKEND=local path.

provider "github" {
  owner = var.github_owner
}

resource "github_repository" "this" {
  for_each = var.repositories

  name        = each.key
  description = each.value.description
  visibility  = each.value.visibility
  topics      = each.value.topics
  has_issues  = each.value.has_issues

  # Give a newly-created repo an initial commit + default branch so the branch_default and
  # branch_protection resources below have something to point at. No-op on imported repos.
  auto_init = true
}

resource "github_branch_default" "this" {
  for_each = var.repositories

  repository = github_repository.this[each.key].name
  branch     = each.value.default_branch
}

resource "github_branch_protection" "this" {
  # Only repos that declared a branch_protection block.
  for_each = {
    for name, cfg in var.repositories : name => cfg
    if cfg.branch_protection != null
  }

  repository_id  = github_repository.this[each.key].node_id
  pattern        = each.value.default_branch
  enforce_admins = each.value.branch_protection.enforce_admins

  required_pull_request_reviews {
    required_approving_review_count = each.value.branch_protection.required_approving_review_count
  }

  # Only emit a required_status_checks block when contexts were supplied, otherwise an empty
  # block would still mark the branch as requiring (zero) checks.
  dynamic "required_status_checks" {
    for_each = length(each.value.branch_protection.required_status_checks) > 0 ? [1] : []
    content {
      strict   = true
      contexts = each.value.branch_protection.required_status_checks
    }
  }
}
