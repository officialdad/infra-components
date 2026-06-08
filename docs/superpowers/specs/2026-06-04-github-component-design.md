# `github` component — design

**Date:** 2026-06-04
**Status:** Approved
**Repos touched:** `infra-components` (the module), `infra-environments-dev` (consumption)

## Goal

A reusable Terraform component that manages GitHub repositories-as-code, consumed by
`infra-environments-dev` via the existing Terragrunt pattern. Dev is the **single owner**
of GitHub-as-code (prod does not re-declare it) so two states never fight over org-scoped
resources.

## Approach

**Repository factory** — one component driven by a `repositories` map input. Each map entry
configures one repo (visibility, description, topics, default branch, optional branch
protection). Adding/changing a repo on the dev side is a single tfvars map edit; the module
never changes. No repos are seeded — dev ships with `repositories = {}` plus a commented
example.

## Module: `infra-components/github/terraform/`

Standard 4-file anatomy.

### `versions.tf`
- `required_version >= 1.5`
- provider `integrations/github` `~> 6.0`

### `variables.tf`
- `global` — accepted **only to satisfy the repo convention**. `_shared.hcl` always injects
  `-var-file=global.tfvars`, so the variable must exist or Terraform errors on an undefined
  var. GitHub resources have no region/tags, so its values are intentionally unused here;
  documented as such.
- `github_owner` (string, default `"officialdad"`) — the org the provider operates on.
- `repositories` — map of objects, key = repo name:

  ```hcl
  map(object({
    description       = optional(string, "")
    visibility        = optional(string, "private")  # private | public | internal
    topics            = optional(list(string), [])
    default_branch    = optional(string, "main")
    has_issues        = optional(bool, true)
    branch_protection = optional(object({
      required_approving_review_count = optional(number, 1)
      required_status_checks          = optional(list(string), [])
      enforce_admins                  = optional(bool, false)
    }))  # null/omitted = no protection
  }))
  ```
  Default `{}`. A `visibility` validation restricts it to `private|public|internal`.

### `main.tf`
- `provider "github" { owner = var.github_owner }` — token read from `GITHUB_TOKEN` env var
  (no secret in git).
- `github_repository.this`        — `for_each = var.repositories`
- `github_branch_default.this`    — `for_each = var.repositories`
- `github_branch_protection.this` — `for_each` only over entries with a `branch_protection`
  block; `pattern` = the repo's default branch.

### `outputs.tf`
- `repository_names` — map key → full name
- `repository_urls`  — map key → `html_url`

## Auth & operational notes (README)
- **First component that needs a secret.** Requires `GITHUB_TOKEN` (PAT or GitHub App token)
  with `repo` (+ `admin:org` if managing org-internal settings). It cannot run on the
  credential-free `TG_BACKEND=local` path the `dummy` component uses.
- **Existing repos:** `github_repository` *creates* repos. To bring an already-existing repo
  under management, `terraform import` it first or Terraform will try to create a duplicate
  and fail. (Not exercised now — dev ships with an empty map.)

## Dev consumption: `infra-environments-dev/`
Thin, identical grain to the other components:
- `components.hcl` — add `github = "github"`.
- `github/versions.hcl` — `locals { github = "main" }` (dev tracks `main`).
- `github/terragrunt.hcl` — `include "root"` + `include "shared"`, no upstream deps.
- `github/terraform.tfvars` — `github_owner = "officialdad"`, `repositories = {}` with a
  commented example entry showing the full per-repo shape.

## Out of scope (YAGNI)
- Teams, team membership, collaborators, repo secrets/variables, org rulesets, webhooks.
  Easy to add as further optional fields/resources later if needed.
- Seeding real repos / importing them.
- Prod wiring (dev is sole owner).
