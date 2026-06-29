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

## Inputs

| Name                      | Type        | Default       | Description                                                        |
| ------------------------- | ----------- | ------------- | ------------------------------------------------------------------ |
| `github_owner`            | string      | `officialdad` | The GitHub org (or user) the provider operates on.                 |
| `default_team`            | string      | `engineers`   | Team slug granted to every repo by default; `""` disables.         |
| `default_team_permission` | string      | `push`        | Default team's access: `pull`/`triage`/`push`/`maintain`/`admin`.  |
| `repositories`            | map(object) | `{}`          | Repositories to manage, keyed by repo name (see shape below).      |

### `repositories` entry shape

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

## Outputs

| Name               | Description                                            |
| ------------------ | ----------------------------------------------------- |
| `repository_names` | Map of key → full name (`owner/repo`).                |
| `repository_urls`  | Map of key → HTML URL.                                |
| `team_grants`      | Map of key → `"team:permission"` from `default_team`. |

## Managing repos that already exist

`github_repository` **creates** repos. To bring an existing repo under management, import it
first or Terraform will try to create a duplicate and fail:

```bash
terraform import 'github_repository.this["my-repo"]' my-repo
```

## Dependencies

None. It does not consume any other component's outputs.
