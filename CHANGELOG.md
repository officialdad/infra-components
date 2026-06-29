# Changelog

All notable changes to the modules in this repo are recorded here.

Format follows [Keep a Changelog](https://keepachangelog.com/), and this repo uses
[Semantic Versioning](https://semver.org/) via git tags (`vMAJOR.MINOR.PATCH`).

**How this connects to the environments repos:** `infra-environments-dev` tracks `main`, so the
`[Unreleased]` changes below are what dev runs. When a change has soaked in dev, cut a tag (see
[CONVENTIONS.md](./CONVENTIONS.md#releasing)) and the version moves out of `[Unreleased]`. Prod
pins that tag, so this file is the human-readable answer to "what's in v0.2.0?".

- **Added** — new modules/features.
- **Changed** — changes to existing behavior (note if it affects inputs/outputs).
- **Fixed** — bug fixes.
- **Removed** — removed features (call out breaking changes loudly).

## [Unreleased]

> **AWS components added alongside GCP — both stacks are kept.** The 0.4.0 GCP work (`network`,
> `compute-engine`) stays as-is; new AWS analogs `vpc` and `ec2` are added next to it so an
> environment can target either cloud. The `global` + `instances`-map interface (including the
> multi-VM `for_each` work merged in #4) is shared verbatim across the AWS/GCP pairs; only the cloud
> resources and field names differ. `github` is cloud-agnostic and untouched. Nothing is removed —
> the GCP modules deleted on an earlier cut of this branch have been restored.

### Added
- **`automation-roles` — AWS CI identity (GitHub-OIDC → IAM role)** (`hashicorp/aws ~> 6.0`), the AWS
  analog of the GCP WIF work. Lets the `infra-environments-dev` pipeline assume a short-lived AWS role
  via GitHub Actions OIDC — **no static `AWS_*` keys**. Creates the OIDC provider (toggleable, since
  it's an account-global singleton) + a role whose trust is **ref/event-scoped by default** (`main`
  apply, `pull_request` plan) with a **least-privilege** policy for exactly what `vpc`+`ec2` need.
  Outputs `role_arn` (→ env repo `AWS_ROLE_ARN` secret) + `oidc_provider_arn`. **Human-applied,
  excluded from the pipeline it bootstraps.**
- **`ec2` — AWS EC2 compute component** (`hashicorp/aws >= 6.37`), the AWS analog of `compute-engine`.
  A thin wrapper over two verified modules: [`terraform-aws-modules/ec2-instance/aws`](https://registry.terraform.io/modules/terraform-aws-modules/ec2-instance/aws)
  (`~> 6.0`) builds the instance + its IAM role/instance profile (`create_iam_instance_profile` with
  the managed `AmazonSSMManagedInstanceCore` policy) and enforces **IMDSv2**; [`terraform-aws-modules/security-group/aws`](https://registry.terraform.io/modules/terraform-aws-modules/security-group/aws)
  (`~> 5.0`) builds a **per-instance** SG. One or more instances via an `instances` map (`for_each`) —
  add a key to add an instance — each with **no public IP** by default. Access is **SSM Session
  Manager** (the IAP/OS Login analog); the SG is **egress-only by default** (SSM dials out via the
  `vpc`'s NAT). Each entry takes a per-instance **`ingress_rules`** list of *named* rules (e.g.
  `["prometheus-http-tcp"]` → 9090) opened **from the VPC CIDR only** (east-west; public exposure is
  the consuming env's job, e.g. a Cloudflare Tunnel in `user_data`). **Bootstrap-agnostic**
  (`user_data` per instance, `""` = none). AMI defaults to the latest **Amazon Linux 2023** via the
  module's `ami_ssm_parameter`. Instance `Name` tag = `<environment_name>-<key>`; outputs a single
  `instances` map keyed by instance key (`name`, `instance_id`, `private_ip`, `ssm_command`).
  Consumes `vpc_id`, `vpc_cidr`, + `subnet_id` from `vpc` — the CIDR (for SG ingress) arrives as a
  **value through the dependency**, not a live `aws_vpc` lookup, so `ec2` plans greenfield on mock
  outputs instead of failing on a non-existent VPC id. Unlike `compute-engine`, there is **no `access_members`**
  — Session Manager rights are an IAM concern on the *caller* (`ssm:StartSession`), not on the module.
  Each entry can attach **extra scoped IAM policies** to its instance role via **`iam_role_policy_arns`**
  (merged *atop* the always-on `AmazonSSMManagedInstanceCore`), so a consumer grants e.g. read of one
  SSM SecureString param — without touching the component.
- **`vpc` — AWS network foundation** (`hashicorp/aws ~> 6.0`), the AWS analog of `network`. A thin
  wrapper over `terraform-aws-modules/vpc/aws` (`~> 6.0`): a VPC + **per-AZ** private/public subnets
  (`az_count`, default `2`; each a `/20` via `cidrsubnet`) + a single **NAT gateway**
  (`enable_nat_gateway`, default `true`) for private-instance egress. Inputs `cidr_block` /
  `az_count` / `enable_nat_gateway`; outputs `vpc_id`, `vpc_cidr_block`, `private_subnet_ids`,
  `public_subnet_ids`, `region`. The GCP analog mapping is `network_self_link` → `vpc_id`, `subnetwork_self_link` →
  `private_subnet_ids[0]`.

### Changed
- **`compute-engine` now honors `global.tags`.** Instance `labels` previously carried only
  `environment` + `managed_by`; they now also include `global.tags`, sanitized to GCP's label rules
  (lowercased, chars outside `[a-z0-9_-]` → `_`), with the env/managed_by labels winning on any
  name clash. In-place update, no recreate. (GCP *networking* resources still can't be labeled — see
  `network`.)
- **Standardized `versions.tf`.** `required_version` is now `>= 1.5.7` across all components (was a
  mix of `>= 1.5` / `>= 1.5.7`); `ec2`'s AWS provider pin is now the bounded `~> 6.37` (was the
  unbounded `>= 6.37`), matching the `~>` style used by the other components.

### Fixed
- **CI now lints `automation-roles`.** It was missing from the `.github/workflows/ci.yml` matrix, so
  it was never `fmt`/`validate`/`tflint`'d.
- **`github` docs.** Dropped a stale reference to the removed `dummy` component and a phantom
  `global` input row — `github` intentionally takes no `global` (now a documented exception in
  CONVENTIONS).

## [0.4.0] - 2026-06-15

> **Cloud pivot:** the org is moving to **GCP**. New components target `hashicorp/google`; the
> AWS modules have been removed (see **Removed** below).

### Added
- `compute-engine` — first GCP compute module (`google_compute_instance`). **Bootstrap-agnostic**:
  runs a caller-supplied `startup_script` (userdata) on first boot, `""` = none. The Docker
  bootstrap and its on/off switch live in the consuming environment (`infra-environments-dev`),
  not in the module (no Ansible, no COS). **No external IP** by default — access is "SSM-like":
  **OS Login + IAP TCP forwarding**
  (`gcloud compute ssh --tunnel-through-iap`), governed by IAM. Grants `roles/compute.osLogin`
  and `roles/iap.tunnelResourceAccessor` to `access_members`. Opts into VPC firewall rules via
  `network_tags` (e.g. `[network.ssh_tag]`); empty default = no tag-scoped inbound. Consumes
  `network`/`subnetwork` from the `network` component. Built for cheap teardown/redeploy (no deletion protection, boot disk
  auto-deletes, `allow_stopping_for_update`), so the VM can be destroyed when idle to save credits.
  Outputs `instance_name`, `internal_ip`, `ssh_command`.

### Changed
- **`network` (replaces AWS `vpc`) — GCP network foundation built on registry modules.** The old
  AWS `vpc` (IGW, public/private subnets per AZ) is gone; the new `network` component is a thin
  wrapper over the verified CFT modules `terraform-google-modules/network/google` (`~> 18.0`) and
  `terraform-google-modules/cloud-router/google` (`~> 9.0`). It creates a custom-mode VPC network
  + one **regional** subnetwork (Private Google Access on), optional **Cloud Router + NAT**
  (`enable_cloud_nat`, default `true`) for private-instance egress, and an **allow-IAP-SSH** rule
  from `35.235.240.0/20` (`enable_iap_ssh`, default `true`) **scoped by `target_tags` to VMs
  wearing the exported `ssh_tag`** (multi-VM ready). Inputs `project_id`, `subnet_cidr`. Outputs
  `network_self_link`, `subnetwork_self_link`, `network_name`, `subnetwork_name`, `region`,
  `ssh_tag`. Pulls in the `google-beta` provider (required by the network module). Replaces the
  hand-written `vpc` rewrite that previously lived on this branch.
- `github` — added per-repo `delete_branch_on_merge` (auto-deletes the head branch on merge,
  default `true`) and an org-wide default-team grant: `default_team` (default `engineers`)
  is granted `default_team_permission` (default `push`) on every managed repo via
  `github_team_repository`; set `default_team = ""` to opt out. Adds a `team_grants` output.
  The team grant requires `GITHUB_TOKEN` with `admin:org`.

### Removed
- **`app-alb` and `postgres-instance` (AWS) — deleted.** Both consumed the old AWS `vpc`
  outputs and are not used by any environment (already dropped from `infra-environments-dev`).
  Removed as part of the GCP pivot rather than left as dead AWS modules. Recoverable from git
  history; will be replaced by GCP equivalents (Cloud Load Balancing / Cloud SQL) if needed.
- **`dummy` — deleted.** The credential-free pipeline-test stub (random/local/null) has served
  its purpose now that real GCP components (`network`, `compute-engine`) exercise the pipeline.

## [0.3.0] - 2026-06-08

### Added
- `github` — repository factory component (`integrations/github` provider). Manages GitHub
  repos as code via a `repositories` map: visibility, description, topics, default branch, and
  optional branch protection. First component requiring a credential (`GITHUB_TOKEN`); intended
  to be owned by `infra-environments-dev` only, since repos are org-scoped.

## [0.2.0] - 2026-06-03

### Added
- `dummy` — credential-free component (random/local/null providers) for exercising the full
  CI/CD pipeline (plan → PR comment → gated apply) without a cloud account.

## [0.1.0] - 2026-06-03

### Added
- Initial module library:
  - `vpc` — VPC with public/private subnets across AZs, IGW, public routing. Outputs
    `vpc_id`, `subnet_ids_list_by_name`.
  - `postgres-instance` — RDS PostgreSQL with subnet group, security group, generated
    (sensitive) master password. Outputs `database_address`, `database_arn`, credentials.
  - `app-alb` — public Application Load Balancer with security group, target group, HTTP listener.

[Unreleased]: https://github.com/officialdad/infra-components/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/officialdad/infra-components/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/officialdad/infra-components/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/officialdad/infra-components/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/officialdad/infra-components/releases/tag/v0.1.0
