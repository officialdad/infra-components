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
pins a version. The environments repos decide which version of each component to use:
`infra-environments-dev` tracks `main`; `infra-environments-prod` pins git tags.

See **[CONVENTIONS.md](./CONVENTIONS.md)** for module anatomy, naming, and the release process,
and **[CHANGELOG.md](./CHANGELOG.md)** for what changed in each tagged version.

## Components

| Component           | Purpose                                          | Key outputs                                   |
| ------------------- | ------------------------------------------------ | --------------------------------------------- |
| `vpc`               | Network foundation (VPC, subnets)                | `vpc_id`, `subnet_ids_list_by_name`           |
| `postgres-instance` | RDS PostgreSQL instance                          | `database_address`, `database_arn` (+secrets) |
| `app-alb`           | Public Application Load Balancer                 | `alb_dns_name`, `alb_arn`, `target_group_arn` |
| `dummy`             | Credential-free CI/CD test (random/local/null)   | `pet_name`, `artifact_path`                    |
| `github`            | GitHub repositories as code (repo factory)       | `repository_names`, `repository_urls`         |

`vpc`, `postgres-instance`, and `app-alb` form a dependency chain:
**`vpc` → `postgres-instance` / `app-alb`**. `dummy` has no dependencies — it exists only to
exercise the pipeline (plan → PR comment → gated apply) without a cloud account, and can be
removed once real components are flowing.

## Anatomy of a component

Each component's `terraform/` directory follows the same layout:

```
<component>/terraform/
├── versions.tf     # required_version + required_providers
├── variables.tf    # inputs (always includes a `global` object, see below)
├── main.tf         # the resources
└── outputs.tf      # values consumed by downstream components
```

### The `global` convention

Every component takes a `global` object carrying environment-wide context
(name, region, tags). The environments repo passes this once via a shared `global.tfvars`,
so individual components stay generic. Example:

```hcl
variable "global" {
  type = object({
    environment_name = string
    deploy_region    = string
    tags             = map(string)
  })
}
```

## Versioning & releasing

Components are versioned with **git tags** (`vMAJOR.MINOR.PATCH`), consumed via `?ref=<tag>`.
Dev can track a branch (`?ref=main`) while iterating; prod pins a tag. The full release/promotion
process is in [CONVENTIONS.md](./CONVENTIONS.md#versioning--releasing).

## Toolchain

- Terraform **1.15.5**, Terragrunt **1.0.7** (the environments repos pin these via
  `.terraform-version` / `.terragrunt-version`).
- CI (`.github/workflows/ci.yml`) runs `terraform fmt` / `validate` / `tflint` per component.

## Notes

- All values are placeholders — no real AWS account IDs, credentials, or hostnames.
- Modules are minimal but **valid and applyable** (real resource blocks), so you can grow them.
- A real apply requires AWS credentials and a state backend, both configured in the env repos.
