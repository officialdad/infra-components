# github

Manages **GitHub repositories as code**. A repository factory: you pass a `repositories` map
and the module creates/configures one repo per entry — visibility, description, topics,
default branch, and optional branch protection. Adding or changing a repo is a single map
edit on the consumer side; the module never changes.

This is the **first component that needs a credential** (a `GITHUB_TOKEN`), so unlike `dummy`
it cannot run on the credential-free `TG_BACKEND=local` path. Because GitHub repos are
**org-scoped, not per-environment**, exactly one environment should own this component —
`infra-environments-dev` is the designated owner.

## What it creates

Per entry in `repositories`:

- `github_repository` — the repo (visibility, description, topics, `has_issues`, `auto_init`).
- `github_branch_default` — sets the default branch.
- `github_branch_protection` — only when the entry includes a `branch_protection` block
  (required reviews, optional required status checks, enforce-admins).

## Auth

The provider reads `GITHUB_TOKEN` from the environment — a PAT or GitHub App token with at
least `repo` scope (`admin:org` if you manage org-internal settings). **No token is stored in
this module or in git.** Export it before running:

```bash
export GITHUB_TOKEN=ghp_...
```

## Inputs

| Name           | Type          | Default        | Description                                                        |
| -------------- | ------------- | -------------- | ------------------------------------------------------------------ |
| `global`       | object        | —              | Env-wide context. Accepted for convention only; **unused** here.   |
| `github_owner` | string        | `officialdad`  | The GitHub org (or user) the provider operates on.                 |
| `repositories` | map(object)   | `{}`           | Repositories to manage, keyed by repo name (see shape below).      |

### `repositories` entry shape

```hcl
repositories = {
  "my-repo" = {
    description    = "What it is"
    visibility     = "private"        # private | public | internal
    topics         = ["terraform"]
    default_branch = "main"
    has_issues     = true

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

| Name               | Description                                  |
| ------------------ | -------------------------------------------- |
| `repository_names` | Map of key → full name (`owner/repo`).       |
| `repository_urls`  | Map of key → HTML URL.                        |

## Managing repos that already exist

`github_repository` **creates** repos. To bring an existing repo under management, import it
first or Terraform will try to create a duplicate and fail:

```bash
terraform import 'github_repository.this["my-repo"]' my-repo
```

## Dependencies

None. It does not consume any other component's outputs.
