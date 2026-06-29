# infra-components

A reusable Terraform module library for the `officialdad` infrastructure. Each top-level
directory is a **component**; the actual Terraform lives in that component's `terraform/`
subdirectory.

This repo is **public** so the environments repos can fetch modules over HTTPS with no auth.
Modules are consumed via a pinned git source, e.g.:

```hcl
terraform {
  source = "git::https://github.com/officialdad/infra-components.git//<component>/terraform?ref=<tag>"
}
```

The `//<component>/terraform` part selects the subdirectory inside this repo, and `?ref=<tag>`
pins a version.

This README is also the **conventions contract** for the `officialdad` IaC repos: the anatomy,
the `global` object, naming, and release process below are shared by all three repos. See
**[CHANGELOG.md](./CHANGELOG.md)** for what changed in each tagged version, and **[CLAUDE.md](./CLAUDE.md)**
for how agents work in this repo (the automated quality gate, design principles, and the
component checklist).

## Repos

| Repo | Role | Module ref |
| --- | --- | --- |
| `infra-components` | Reusable Terraform modules | tagged releases |
| `infra-environments-dev` | Dev environment (ungated) | tracks `main` |
| `infra-environments-prod` | Prod environment (gated) | pinned tags |

## Components

> **Clouds:** both **AWS** (`hashicorp/aws`) and **GCP** (`hashicorp/google`) modules are kept here,
> so an environment can pick either stack. See [CHANGELOG.md](./CHANGELOG.md) for the history.

| Component        | Cloud  | Purpose                                          | Key outputs                                     |
| ---------------- | ------ | ------------------------------------------------ | ----------------------------------------------- |
| `vpc`            | AWS    | Network foundation — wraps `terraform-aws-modules/vpc` (VPC + per-AZ subnets + NAT) | `vpc_id`, `private_subnet_ids`, `public_subnet_ids` |
| `ec2`            | AWS    | One or more EC2 instances (`instances` map, bootstrap-agnostic) via the `ec2-instance` + `security-group` modules; SSM access, no public IP, per-instance named `ingress_rules` | `instances` (map keyed by instance key) |
| `network`        | GCP    | Network foundation — custom-mode VPC + regional subnet + Cloud NAT + IAP-SSH firewall (wraps Google Cloud Foundation Toolkit) | `network_name`, `subnetwork_self_link`, `ssh_tag` |
| `compute-engine` | GCP    | One or more Compute Engine VMs (`instances` map, bootstrap-agnostic); OS Login + IAP access, no external IP | `instances` (map keyed by instance key) |
| `github`         | GitHub | GitHub repositories as code (repo factory)       | `repository_names`, `repository_urls`           |
| `automation-roles` | AWS  | CI identity — GitHub Actions OIDC provider + the least-privilege IAM role the pipeline assumes (no static keys) | `role_arn`, `oidc_provider_arn` |

The components form two parallel dependency chains, one per cloud:
**`vpc` → `ec2`** (AWS) and **`network` → `compute-engine`** (GCP) — in each, instances launch into
the network the foundation component outputs. `github` and `automation-roles` are standalone
(no network); `automation-roles` is a human-applied CI bootstrap, kept out of its own pipeline.

## Anatomy of a component

Each component is a directory with a `terraform/` subdir:

```
<component>/
├── README.md          # inputs/outputs table, dependencies
└── terraform/
    ├── versions.tf    # required_version (min floor, >= 1.5.7) + required_providers (pinned ~> ranges)
    ├── variables.tf   # inputs; first variable is always `global` (except `github`, see below)
    ├── main.tf        # provider + resources
    └── outputs.tf     # values consumed by downstream components
```

### The `global` object

Every component takes a `global` object as its first variable, carrying environment-wide context
(name, region, tags) so modules stay generic. The environments repo passes it once via a shared
`global.tfvars`.

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
`merge(var.global.tags, { ... })` on every resource. On GCP, `global.tags` is sanitized into
resource **labels** where the provider supports them (e.g. the `compute-engine` instance); GCP
*networking* resources can't be labeled, so only naming carries through there.

> **One exception:** `github` takes **no `global`**. Its resources are org-scoped, not
> environment-scoped, and `github_repository` has nothing to tag — a `global` input would be a
> dead declaration (which `tflint`'s recommended preset flags). Every other component takes
> `global` as its first variable.

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

Modules are versioned with **git tags** (`vMAJOR.MINOR.PATCH`), consumed via `?ref=<tag>`. Dev can
track a branch (`?ref=main`) while iterating; prod pins a tag.

- **MAJOR** — breaking input/output change (callers must edit their config). Call it out loudly
  in CHANGELOG.
- **MINOR** — new feature, backward compatible.
- **PATCH** — bug fix, no interface change.

### Releasing (manual)

1. Make the module change on a branch, open a PR, merge to `main`.
2. `infra-environments-dev` (tracks `main`) picks it up — apply and let it soak.
3. Update [CHANGELOG.md](./CHANGELOG.md):
   - Move `[Unreleased]` content into a new `## [X.Y.Z] - YYYY-MM-DD` section.
   - Add a compare link at the bottom for the new version.
   - Update the `[Unreleased]` link to `compare/vX.Y.Z...HEAD`.
   ```
   [Unreleased]: https://github.com/officialdad/infra-components/compare/vX.Y.Z...HEAD
   [X.Y.Z]: https://github.com/officialdad/infra-components/compare/vPREV...vX.Y.Z
   ```
4. Commit the CHANGELOG update, tag, and push both in one command:
   ```bash
   git add CHANGELOG.md
   git commit -m "vX.Y.Z <short description>"
   git tag vX.Y.Z
   git push origin main vX.Y.Z
   ```
   `git push origin main vX.Y.Z` pushes the branch and tag atomically — avoids
   the tag landing on a different commit if something races, and keeps the push log clean.
5. Promote to prod: PR in `infra-environments-prod` bumping the component's `versions.hcl`
   (`"vOLD"` → `"vX.Y.Z"`), reviewed, then apply.

## Commits

Plain, imperative subject lines. Reference an issue if there is one. (We deliberately do **not**
require conventional-commits / semantic-release — tagging is manual and deliberate.)

## Toolchain

- Terraform **1.15.5**, Terragrunt **1.0.7** (the environments repos pin these via
  `.terraform-version` / `.terragrunt-version`).
- CI (`.github/workflows/ci.yml`) runs `terraform fmt` / `validate` / `tflint` per component.

## Notes

- All values are placeholders — no real AWS/GCP account IDs, credentials, or hostnames.
- Modules are minimal but **valid and applyable** (real resource blocks), so you can grow them.
- A real apply requires the relevant cloud credentials (AWS or GCP) and a state backend, both configured in the env repos.
