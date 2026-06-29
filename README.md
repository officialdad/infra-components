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

- All values are placeholders — no real AWS/GCP account IDs, credentials, or hostnames.
- Modules are minimal but **valid and applyable** (real resource blocks), so you can grow them.
- A real apply requires the relevant cloud credentials (AWS or GCP) and a state backend, both configured in the env repos.
