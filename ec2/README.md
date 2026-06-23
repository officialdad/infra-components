# ec2

**One or more AWS EC2 instances**, defined as a map (`instances`) and fanned out with `for_each` —
add a key to add an instance. Each instance has **no public IP** by default; access follows AWS
**SSM Session Manager**: you open a session through your own IAM identity (no public SSH port, no key
pairs to manage). The module is **bootstrap-agnostic** — it runs whatever `user_data` each instance
passes (e.g. a Docker install), but owns no userdata itself.

## What it creates

For each entry in `instances` (keyed by a short name — that key also keys the `instances` **output**; the instance's `Name` tag is `<environment_name>-<key>`, so a `postiz` key → output `instances["postiz"]` whose `.name` is `dev-postiz`):

- `aws_instance` — the EC2 instance. No public IP by default. AMI defaults to the latest Amazon
  Linux 2023 (resolved per-region via the public SSM parameter), which ships the SSM agent
  preinstalled. Runs that entry's `user_data` on first boot (empty string = no bootstrap).
  **This module is bootstrap-agnostic** — the actual first-boot script is **userdata owned by the
  consuming environment**, not baked into the module. See "Bootstrap / userdata" below.

Shared by every instance (created once):

- `aws_security_group` — **egress-only** (all protocols to `0.0.0.0/0`), **no inbound rules**. SSM
  reaches the instance outbound via the `vpc`'s NAT, so no ingress is needed.
- `aws_iam_role` + `aws_iam_role_policy_attachment` + `aws_iam_instance_profile` — an instance
  profile trusting `ec2.amazonaws.com` with the AWS-managed **`AmazonSSMManagedInstanceCore`**
  policy attached. This is what lets the SSM agent register the instance for Session Manager.

## Access model ("SSM Session Manager")

```
you / CI principal
   │  (your IAM identity: ssm:StartSession)
   ▼
SSM  ──session──▶  EC2   (no public IP, no inbound SG rule; agent dials out via NAT)
```

Connect with:

```bash
aws ssm start-session --target <instance-id> --region <region>
```

Each `instances[<key>].ssm_command` output prints this for you. Unlike the GCP version's
`access_members`, **granting humans access is out of this module's scope** — Session Manager rights
live on the *caller's* IAM (`ssm:StartSession` on the target), not on the instance. The instance side
only needs the `AmazonSSMManagedInstanceCore` profile this module attaches.

## Bootstrap / userdata

The module does **not** know what to install — it just runs whatever `user_data` string the caller
passes on first boot. Pass `""` (the default) for a plain instance.

The **consuming environment owns the bootstrap**. In `infra-environments-dev` a bootstrap script is
read with `file()` and passed as that instance's `user_data` inside the `instances` map:

```hcl
inputs = {
  vpc_id    = dependency.vpc.outputs.vpc_id
  subnet_id = dependency.vpc.outputs.private_subnet_ids[0]

  instances = {
    postiz = {
      instance_type = "t3.small"
      user_data     = file("${get_terragrunt_dir()}/userdata/docker-bootstrap.sh")
    }
  }
}
```

A Docker bootstrap needs outbound internet (the package repos, registries), which the `vpc`'s
NAT gateway provides to these otherwise-private instances.

## Auth

Provider needs AWS credentials (env vars, shared config, or an instance/CI role); region comes from
`var.global.deploy_region`. The principal running `apply` needs rights to create EC2 instances,
security groups, and IAM roles/instance profiles. To *connect* via Session Manager, your own IAM
identity needs `ssm:StartSession` on the target instance.

## Inputs

| Name        | Type        | Default | Description                                                                                       |
| ----------- | ----------- | ------- | ------------------------------------------------------------------------------------------------ |
| `global`    | object      | —       | Env-wide context (`environment_name`, `deploy_region`, `tags`).                                  |
| `vpc_id`    | string      | —       | VPC the instances and their security group live in (from `vpc.vpc_id`).                            |
| `subnet_id` | string      | —       | Subnet all instances launch into (from `vpc.private_subnet_ids[0]`). Use a **private** subnet for the no-public-IP, SSM-only model. |
| `instances` | map(object) | `{}`    | Instances to create, keyed by short name. Per-instance fields below; each entry overrides only what it needs. |

Per-instance fields inside each `instances` entry (all optional):

| Field               | Default     | Description                                                                  |
| ------------------- | ----------- | --------------------------------------------------------------------------- |
| `instance_type`     | `t3.micro`  | EC2 instance type.                                                          |
| `ami`               | `""`        | AMI id. Empty → latest Amazon Linux 2023 (resolved per-region via SSM).      |
| `root_disk_size_gb` | `20`        | Root EBS volume size in GB.                                                  |
| `assign_public_ip`  | `false`     | Attach a public IP. Leave `false` for the SSM-only model.                    |
| `user_data`         | `""`        | First-boot script (userdata). Empty = no bootstrap. Supplied by the env.    |

> **No `access_members`:** the GCP version granted OS Login + IAP per principal because access lived
> on the resource. On AWS, Session Manager access is an IAM concern on the *caller's* side
> (`ssm:StartSession`), so it has no place in this module. Env identity (`vpc_id`, `subnet_id`) is
> required with no default; the cost-safe *how* knobs (`t3.micro`, 20 GB) keep defaults, since a
> forgotten value there is harmless.

## Outputs

| Name        | Type        | Description                                                                                                                          |
| ----------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `instances` | map(object) | Per-instance details keyed by instance key. Each value has `name`, `instance_id`, `private_ip`, and a ready-to-run `ssm_command` (`aws ssm start-session …`). |

## Dependencies

Consumes `vpc_id` and `subnet_id` from the `vpc` component. Relies on the `vpc`'s NAT gateway
for outbound (so the SSM agent can dial out and any bootstrap can fetch packages).
