# infra-components-template

A **sanitized, learning-oriented** Terraform module library, modeled on a production
Terragrunt + Terraform setup. Each top-level directory is a **reusable component**; the actual
Terraform lives in that component's `terraform/` subdirectory.

These modules are meant to be consumed by a separate **environments** repo
(see `infra-environments-template`) via a pinned git source:

```hcl
terraform {
  source = "git::https://github.com/<YOUR_ORG>/infra-components-template.git//<component>/terraform?ref=<tag>"
}
```

The `//<component>/terraform` part selects the subdirectory inside this repo, and `?ref=<tag>`
pins a version (a git tag, branch, or commit). The environments repo decides which version of
each component to use.

## Components

| Component           | Purpose                              | Key outputs                                   |
| ------------------- | ------------------------------------ | --------------------------------------------- |
| `vpc`               | Network foundation (VPC, subnets)    | `vpc_id`, `subnet_ids_list_by_name`           |
| `postgres-instance` | RDS PostgreSQL instance              | `database_address`, `database_arn` (+secrets) |
| `app-alb`           | Public Application Load Balancer     | `alb_dns_name`, `alb_arn`, `target_group_arn` |

They form a natural dependency chain: **`vpc` → `postgres-instance` / `app-alb`**.

## Anatomy of a component

Each component's `terraform/` directory follows the same layout:

```
<component>/terraform/
├── versions.tf     # required_terraform + required_providers
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

## Versioning

Components are versioned with **git tags**. Tag a release and the environments repo references it
via `?ref=<tag>`. For a starter setup you can also reference a branch (e.g. `?ref=main`) while
iterating.

## This is a template

- No real AWS account, credentials, or hostnames are referenced — all values are placeholders.
- Modules are minimal but **valid and applyable** (real resource blocks), so you can grow them.
- Apply requires your own AWS credentials and a real state backend (configured in the env repo).
