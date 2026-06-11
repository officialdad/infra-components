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
  `network_tags` (e.g. `[vpc.ssh_tag]`); empty default = no tag-scoped inbound. Consumes
  `network`/`subnetwork` from the `vpc` component. Built for cheap teardown/redeploy (no deletion protection, boot disk
  auto-deletes, `allow_stopping_for_update`), so the VM can be destroyed when idle to save credits.
  Outputs `instance_name`, `internal_ip`, `ssh_command`.
- `github` — repository factory component (`integrations/github` provider). Manages GitHub
  repos as code via a `repositories` map: visibility, description, topics, default branch, and
  optional branch protection. First component requiring a credential (`GITHUB_TOKEN`); intended
  to be owned by `infra-environments-dev` only, since repos are org-scoped.

### Changed
- **`vpc` — rewritten AWS → GCP (breaking).** Was an AWS VPC (IGW, public/private subnets per
  AZ); now a `google_compute_network` + one **regional** `google_compute_subnetwork` (Private
  Google Access on), optional **Cloud Router + Cloud NAT** (`enable_cloud_nat`, default `true`)
  for private-instance egress, and firewall rules including **allow-IAP-SSH** from
  `35.235.240.0/20` (`enable_iap_ssh`, default `true`), **scoped by `target_tags` to VMs wearing
  the exported `ssh_tag`** (multi-VM ready). New input `project_id`. **Outputs changed:**
  `vpc_id`/`cidr_block`/`subnet_ids_list_by_name` → `network_self_link`, `subnetwork_self_link`,
  `network_name`, `subnetwork_name`, `region`, `ssh_tag`. Callers must update.
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
  its purpose now that real GCP components (`vpc`, `compute-engine`) exercise the pipeline.

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

[Unreleased]: https://github.com/officialdad/infra-components/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/officialdad/infra-components/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/officialdad/infra-components/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/officialdad/infra-components/releases/tag/v0.1.0
