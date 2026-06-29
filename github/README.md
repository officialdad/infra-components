# github

Manages **GitHub repositories as code**. A repository factory: you pass a `repositories` map
and the module creates/configures one repo per entry — visibility, description, topics,
default branch, and optional branch protection. Adding or changing a repo is a single map
edit on the consumer side; the module never changes.

This component **needs a credential** (a `GITHUB_TOKEN`), so it cannot run on the credential-free
`TG_BACKEND=local` path. Because GitHub repos are **org-scoped, not per-environment**, exactly one
environment should own this component — `infra-environments-dev` is the designated owner.

> **Exception to the `global` convention:** unlike every other component, `github` takes **no
> `global` object**. Its resources are org-scoped (not environment-scoped) and `github_repository`
> has nothing to tag, so a `global` input would be dead — and the repo's `tflint` (recommended
> preset) flags unused declarations. See [README.md](../README.md#the-global-object).

## What it creates

Per entry in `repositories`:

- `github_repository` — the repo (visibility, description, topics, `has_issues`, `auto_init`,
  `delete_branch_on_merge`). Head branches are auto-deleted on merge by default.
- `github_branch_default` — sets the default branch.
- `github_branch_protection` — only when the entry includes a `branch_protection` block
  (required reviews, optional required status checks, enforce-admins).

Org-wide (one grant per repo, not configured per entry):

- `github_team_repository` — grants `default_team` access to **every** managed repo at
  `default_team_permission`. Skipped entirely when `default_team` is `""`. The team must
  already exist in the org — this component grants access, it does not create teams.

## Auth

The provider reads `GITHUB_TOKEN` from the environment — a PAT or GitHub App token with at
least `repo` scope. **`admin:org` is required** to manage the `default_team` grant (and any
org-internal settings); without it `plan` succeeds but `apply` fails on the team grant. **No
token is stored in this module or in git.** Export it before running:

```bash
export GITHUB_TOKEN=ghp_...
```

## Dependencies

None — `github` consumes no other component's outputs. It owns org-scoped GitHub resources and is
run by a single environment (`infra-environments-dev`).

## Managing repos that already exist

`github_repository` **creates** repos. To bring an existing repo under management, import it first
or Terraform will try to create a duplicate and fail:

```bash
terraform import 'github_repository.this["my-repo"]' my-repo
```

### `repositories` entry shape

The generated Inputs table renders `repositories` as one `map(object({…}))`. A full entry:

```hcl
repositories = {
  "my-repo" = {
    description    = "What it is"
    visibility     = "private"        # private | public | internal
    topics         = ["terraform"]
    default_branch = "main"
    has_issues     = true

    delete_branch_on_merge = true   # auto-delete head branch on merge (default true)

    # Omit this block entirely to leave the branch unprotected.
    branch_protection = {
      required_approving_review_count = 1
      required_status_checks          = ["ci"]   # status check contexts; [] = none
      enforce_admins                  = false
    }
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| default\_team | Team slug granted access to every managed repo by default. Empty string disables the default grant. The team must already exist in the org. | `string` | `"engineers"` | no |
| default\_team\_permission | Permission the default team receives on each repo. | `string` | `"push"` | no |
| github\_owner | The GitHub organization (or user) the provider operates on. | `string` | `"officialdad"` | no |
| repositories | Repositories to manage, keyed by repo name. Each value configures one repo; omit branch\_protection to leave the default branch unprotected. | <pre>map(object({<br/>    description            = optional(string, "")<br/>    visibility             = optional(string, "private")<br/>    topics                 = optional(list(string), [])<br/>    default_branch         = optional(string, "main")<br/>    has_issues             = optional(bool, true)<br/>    delete_branch_on_merge = optional(bool, true)<br/>    branch_protection = optional(object({<br/>      required_approving_review_count = optional(number, 1)<br/>      required_status_checks          = optional(list(string), [])<br/>      enforce_admins                  = optional(bool, false)<br/>    }))<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| repository\_names | Map of repository key -> full name (owner/repo). |
| repository\_urls | Map of repository key -> HTML URL. |
| team\_grants | Map of repository key -> "team:permission" granted by the default team. |
<!-- END_TF_DOCS -->
