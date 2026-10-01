# ebs-volume

One or more standalone **AWS EBS data volumes**, defined as a map (`volumes`) and fanned out with
`for_each` — persistent, encrypted, and **decoupled from any EC2 instance lifecycle**, so an
environment can destroy and re-apply its `ec2` compute while the data on these volumes survives.

## What it creates

- **An `aws_ebs_volume` per `volumes` entry** — `gp3`, `20` GB, **always `encrypted`**, named
  `<environment_name>-<key>` and tagged with `common_tags`. Lives in that entry's `availability_zone`.
  Its `volume_id`, `arn`, `availability_zone`, and `name` are returned in the `volumes` output under
  the same map key.
- **Daily snapshots, opt-in per entry** — set `snapshot` (even `{}`) and the volume gets a
  **`Backup = "<environment_name>-<key>"` tag**, plus one **`aws_dlm_lifecycle_policy`** that targets
  that tag, snapshots once a day at `18:00` UTC (02:00 Asia/Kuala_Lumpur), keeps `7`, and sets
  `copy_tags = true` so each snapshot carries the `Backup` tag. All entries share one
  **`aws_iam_role`** named `<environment_name>-ebs-volume-dlm` with the AWS-managed
  `AWSDataLifecycleManagerServiceRole` attached. `snapshot = null` (default) creates none of this.

> ⚠️ **AZ-locked** — `availability_zone` is required and must match the AZ of the subnet the consuming
> instance launches into, or the instance can't attach it. The dev `vpc` is single-AZ today, so this
> is just that AZ.
>
> ⚠️ **Snapshots select on `Backup`, never `Name`** — `Name` is what the instance attaches by and
> can drift; a policy keyed on it would stop snapshotting with no error. Never put a `Backup` tag
> on any other volume (a restore-test copy included) or DLM snapshots it too. Snapshots are
> **crash-consistent** (no pre/post scripts), and DLM deletes any snapshot past `retain_count`.
>
> ⚠️ **Nothing in this module stops a destroy** — persistence is the *environment's* job. Set
> Terragrunt `prevent_destroy = true` on the unit that owns the volume so it's never in the normal
> apply/destroy cycle. `final_snapshot` (default `false`) is an opt-in recovery net, not a lock.

## Attachment (env-owned)

This module **creates the volume only — it never attaches it**, keeping `ec2` unchanged and destroy
ordering simple. The consuming environment's `user_data`:

- finds the volume by its **`Name` tag** (`volumes[<key>].name`), attaches it, **formats-once**, and
  mounts it — then points the app's data dirs (and any host-generated secret) at the mount.
- needs `ec2:AttachVolume` / `ec2:DetachVolume` / `ec2:DescribeVolumes` on the instance role, **scoped
  to this volume's ARN** — compose that grant with the **`iam-policy`** component and feed it through
  `ec2`'s existing `iam_role_policy_arns`. No change to the `ec2` module.

## Auth

Provider needs AWS credentials (env vars / shared config / CI role) — supplied out-of-band, none
stored here. Region comes from `var.global.deploy_region`. The principal running `apply` needs
`ec2:CreateVolume` / `ec2:CreateTags` / `ec2:DeleteVolume` (and `ec2:DescribeVolumes`). With
`snapshot` set it also needs `dlm:*` and IAM on `<env>-ebs-volume-dlm` (`automation-roles` grants both).

## Dependencies

None — a leaf store. `availability_zone` is supplied directly (it must match the AZ the consuming
`ec2` instance's subnet sits in). The downstream wiring — instance self-attach by `Name` tag + the
scoped IAM grant — is described under **Attachment** above; it lives in the environment, not here.

### `volumes` entry shape

The generated Inputs table renders `volumes` as one `map(object({…}))`. Per-field intent (the map
**key** is the volume's purpose — it sets the `Name` tag `<env>-<key>` the instance attaches by):

- `availability_zone` (required) — AZ the volume lives in; identity/placement, no default. AZ-locked.
- `size_gb` (`20`) — volume size in GiB.
- `type` (`gp3`) — EBS volume type.
- `iops` (unset) — provisioned IOPS; valid only for `gp3` / `io1` / `io2` (AWS rejects it otherwise).
  Unset → the type's default.
- `throughput` (unset) — throughput in MiB/s; valid only for `gp3`. Unset → the type's default.
- `final_snapshot` (`false`) — when `true`, a destroy leaves a recovery snapshot (the volume's tags
  migrate to it). Opt-in; the hard destroy-guard is the env's Terragrunt `prevent_destroy`.
- `snapshot` (`null`) — daily DLM snapshots; `null` means none. `{}` takes both defaults:
  - `times` (`["18:00"]`) — one UTC `HH:MM`. DLM allows a single start time per schedule.
  - `retain_count` (`7`) — snapshots kept, `1`-`1000`.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| global | Environment-wide context injected by the environments repo (name, region, tags). | <pre>object({<br/>    environment_name = string<br/>    deploy_region    = string<br/>    tags             = map(string)<br/>  })</pre> | n/a | yes |
| volumes | EBS data volumes keyed by short name; each entry overrides only what it needs. Name tag = "<env>-<key>" — the value the consuming instance self-attaches by. availability\_zone is required and AZ-locked: it must match the AZ of the subnet the instance launches into. encrypted is always true. final\_snapshot defaults false (opt in for a recovery snapshot on destroy); the env owns hard destroy-protection via Terragrunt prevent\_destroy. snapshot defaults null (no backups); set it (even as {}) to tag the volume Backup = "<env>-<key>" and create a daily DLM snapshot policy on that tag. snapshot.times is one UTC HH:MM (default 18:00 = 02:00 Asia/Kuala\_Lumpur), snapshot.retain\_count is how many snapshots to keep (default 7). | <pre>map(object({<br/>    availability_zone = string<br/>    size_gb           = optional(number, 20)<br/>    type              = optional(string, "gp3")<br/>    iops              = optional(number)<br/>    throughput        = optional(number)<br/>    final_snapshot    = optional(bool, false)<br/>    snapshot = optional(object({<br/>      times        = optional(list(string), ["18:00"])<br/>      retain_count = optional(number, 7)<br/>    }))<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| volumes | Created EBS volumes keyed by their volumes-map key. `name` is the Name tag the consuming instance discovers and self-attaches by. `backup_tag` is the Backup tag value snapshots are listed by and `snapshot_policy` the DLM policy id; both are null when the entry has no `snapshot`. |
<!-- END_TF_DOCS -->
