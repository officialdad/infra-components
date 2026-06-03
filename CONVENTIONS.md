# Conventions

Shared conventions for the `officialdad` IaC repos. Keep this short and followed — it's the
contract that lets two people work without stepping on each other.

## Repos

| Repo | Role | Module ref |
| --- | --- | --- |
| `infra-components` | Reusable Terraform modules | tagged releases |
| `infra-environments-dev` | Dev environment (ungated) | tracks `main` |
| `infra-environments-prod` | Prod environment (gated) | pinned tags |

## Module anatomy

Each component is a directory with a `terraform/` subdir:

```
<component>/
├── README.md          # inputs/outputs table, dependencies
└── terraform/
    ├── versions.tf    # required_version + required_providers (pinned ~> ranges)
    ├── variables.tf   # inputs; first variable is always `global` (see below)
    ├── main.tf        # provider + resources
    └── outputs.tf     # values consumed by downstream components
```

## The `global` object

Every module takes a `global` object as its first variable, carrying environment-wide context
so modules stay generic. The environments repo passes it once via `global.tfvars`.

```hcl
variable "global" {
  type = object({
    environment_name = string
    deploy_region    = string
    tags             = map(string)
  })
}
```

Use it for naming and tags: `"${var.global.environment_name}-vpc"`, and
`merge(var.global.tags, { ... })` on every resource.

## Naming

Deterministic and readable — no random suffixes (we're single-region, two environments; we
don't need global-uniqueness hashing).

- **Resources:** `<environment_name>-<component>[-<purpose>]`
  e.g. `dev-vpc`, `prod-app-sg`, `prod-app-alb-tg`.
- **State buckets:** `tfstate-officialdad-<env>-<region-or-CHANGEME>` (one bucket per environment,
  separate AWS accounts for dev vs prod).
- **State keys:** one per component, set automatically by Terragrunt via
  `${path_relative_to_include()}/terraform.tfstate`.
- **Tags:** always include `Environment`, `ManagedBy = "terraform"`, plus `var.global.tags`.

## Versioning & releasing

Modules are versioned with **git tags** (`vMAJOR.MINOR.PATCH`), consumed via `?ref=<tag>`.

- **MAJOR** — breaking input/output change (callers must edit their config). Call it out loudly
  in CHANGELOG.
- **MINOR** — new feature, backward compatible.
- **PATCH** — bug fix, no interface change.

### Releasing (manual)

1. Make the module change on a branch, open a PR, merge to `main`.
2. `infra-environments-dev` (tracks `main`) picks it up — apply and let it soak.
3. Move the change from `[Unreleased]` to a new version section in
   [CHANGELOG.md](./CHANGELOG.md), with the date.
4. Tag and push:
   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```
5. Promote to prod: PR in `infra-environments-prod` bumping the component's `versions.hcl`
   (`"v0.1.0"` → `"v0.2.0"`), reviewed, then apply.

## Commits

Plain, imperative subject lines. Reference an issue if there is one. (We deliberately do **not**
require conventional-commits / semantic-release — tagging is manual and deliberate.)
