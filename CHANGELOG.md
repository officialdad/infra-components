# Changelog

All notable changes to the modules in this repo are recorded here.

Format follows [Keep a Changelog](https://keepachangelog.com/), and this repo uses
[Semantic Versioning](https://semver.org/) via git tags (`vMAJOR.MINOR.PATCH`).

**Style — keep it lean:** one line per change, `**scope:** imperative summary`. The *why* and *how*
live in the PR and commit, not here. CI drafts the `[Unreleased]` entries from Conventional Commits
and posts them as a comment on your PR (config: [`cliff.toml`](./cliff.toml)); curate them in — trim
noise, keep only consumer-facing changes, add a short narrative blockquote only for a big shift.
Tagging stays manual (see [README](./README.md#versioning--releasing)).

**How this connects to the environments repos:** `infra-environments-dev` tracks `main`, so the
`[Unreleased]` changes below are what dev runs. When a change has soaked in dev, cut a tag (see
[README.md](./README.md#versioning--releasing)) and the version moves out of `[Unreleased]`. Prod
pins that tag, so this file is the human-readable answer to "what's in v0.2.0?".

- **Added** — new modules/features.
- **Changed** — changes to existing behavior (note if it affects inputs/outputs).
- **Fixed** — bug fixes.
- **Removed** — removed features (call out breaking changes loudly).

## [Unreleased]

## [0.6.0] - 2026-06-30

### Added
- **vpc:** `azs` output exposing the ordered AZ list the subnets sit in (`azs[i]` is the AZ of `private_subnet_ids[i]`/`public_subnet_ids[i]`) — lets an env source an AZ-locked input (e.g. `ebs-volume.availability_zone`) instead of hardcoding it or adding its own lookup ([#19](https://github.com/officialdad/infra-components/issues/19))
- **iam-policy:** generic AWS IAM policy factory — env-authored JSON documents become named/tagged `aws_iam_policy`; outputs `policy_arns` (feeds `ec2` `iam_role_policy_arns`)
- **ebs-volume:** standalone encrypted EBS data volumes (`volumes` map) in their own state — decoupled from the `ec2` instance lifecycle so data survives a compute destroy/apply; outputs `volumes` (instance self-attaches by `Name` tag). No `ec2` change
- **ci:** `precommit-coverage` canary — a PR changing `.tf` fails loudly if the pre-commit Terraform hooks report `(no files to check)` instead of running, closing the silent local-gate gap ([#21](https://github.com/officialdad/infra-components/issues/21))

### Changed
- **automation-roles:** CI role may manage `iam:*Policy` scoped to `policy/<env>-*` so the pipeline can apply `iam-policy`
- **ci:** bump `antonbabenko/pre-commit-terraform` `v1.99.0` → `v1.108.0` for upstream staged-file handling fixes ([#21](https://github.com/officialdad/infra-components/issues/21))
- **ci:** derive the validate matrix from the filesystem (each `<component>/terraform/` dir) instead of a hand-maintained list, so a new component is validated automatically ([#21](https://github.com/officialdad/infra-components/issues/21))

### Fixed
- **release.sh:** annotate the `vX.Y.Z` tag (`git tag -m`) so tagging no longer aborts under `tag.gpgsign`/`forceSignAnnotated` — the release commit and tag are always created together

## [0.5.0] - 2026-06-30

> **AWS added alongside GCP — both stacks kept.** New AWS analogs `vpc` / `ec2` / `automation-roles`
> sit beside the GCP `network` / `compute-engine`; the shared `global` + `instances`-map interface is
> identical across the pairs (only cloud resources and field names differ). Nothing removed.

### Added
- **automation-roles:** AWS CI identity — GitHub-OIDC → least-privilege IAM role for `vpc`+`ec2`, no static keys; human-applied, off-pipeline. Outputs `role_arn`, `oidc_provider_arn`
- **ec2:** AWS EC2 component wrapping `ec2-instance` + `security-group` — `instances` map, no public IP, SSM-only access, IMDSv2; per-instance `ingress_rules` (VPC-CIDR-scoped) + `iam_role_policy_arns`; Amazon Linux 2023 by default
- **vpc:** AWS network foundation wrapping `terraform-aws-modules/vpc` — per-AZ public/private subnets + single NAT gateway

### Changed
- **compute-engine:** honor `global.tags` as sanitized GCP labels (parity with AWS; in-place, no recreate)
- **versions.tf:** require Terraform `>= 1.5.7` across all components; bound `ec2`'s AWS provider to `~> 6.37`

### Fixed
- **github:** drop a phantom `global` input row from the docs — `github` takes no `global` (documented exception)

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

[Unreleased]: https://github.com/officialdad/infra-components/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/officialdad/infra-components/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/officialdad/infra-components/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/officialdad/infra-components/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/officialdad/infra-components/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/officialdad/infra-components/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/officialdad/infra-components/releases/tag/v0.1.0
