# ec2

**One or more AWS EC2 instances**, defined as a map (`instances`) and fanned out with `for_each` —
add a key to add an instance. Each instance has **no public IP** by default; access follows AWS
**SSM Session Manager**: you open a session through your own IAM identity (no public SSH port, no key
pairs to manage). The module is **bootstrap-agnostic** — it runs whatever `user_data` each instance
passes (e.g. a Docker install), but owns no userdata itself.

## What it creates

This component is a **thin wrapper** over two verified registry modules — it manages no raw
`aws_instance` / `aws_security_group` / IAM resources itself:

| Wraps | Version | Provides |
| ----- | ------- | -------- |
| [`terraform-aws-modules/ec2-instance/aws`](https://registry.terraform.io/modules/terraform-aws-modules/ec2-instance/aws) | `~> 6.0` | the instance + its IAM role/instance profile |
| [`terraform-aws-modules/security-group/aws`](https://registry.terraform.io/modules/terraform-aws-modules/security-group/aws) | `~> 5.0` | a per-instance SG, with named ingress rules |

For each entry in `instances` (keyed by a short name — that key also keys the `instances` **output**; the instance's `Name` tag is `<environment_name>-<key>`, so a `postiz` key → output `instances["postiz"]` whose `.name` is `dev-postiz`), it builds:

- **An EC2 instance** (ec2-instance module). No public IP by default; OS is selectable per instance —
  a literal `ami` id wins, else `ami_ssm_parameter` tracks the latest image for that OS, resolved
  per-region via SSM (default: Amazon Linux 2023; e.g. point it at Canonical's parameter to track
  latest Ubuntu); **IMDSv2 is enforced** (`http_tokens = "required"`). Runs that entry's `user_data` on first boot
  (empty = no bootstrap). The module also builds the instance's **IAM role + instance profile**
  (`create_iam_instance_profile`) with the AWS-managed **`AmazonSSMManagedInstanceCore`** policy —
  what registers the instance for Session Manager. Attach extra scoped policies per instance via
  `iam_role_policy_arns` (e.g. read one SSM SecureString param). **Bootstrap-agnostic** — the first-boot
  script is **userdata owned by the consuming environment**, not baked in. See "Bootstrap / userdata" below.
- **A per-instance security group** (security-group module). **Egress-only by default** (SSM dials
  out via the `vpc`'s NAT, so no inbound is needed). Set `ingress_rules` to open named service ports
  (e.g. `["prometheus-http-tcp"]` → 9090); these are reachable **from the VPC CIDR only**, never the
  internet. See "Exposing a service" below.

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

Each `instances[<key>].ssm_command` output prints this for you. **Granting humans access is out of
this module's scope** — Session Manager rights live on the *caller's* IAM (`ssm:StartSession` on the
target), not on the instance. The instance side only needs the `AmazonSSMManagedInstanceCore` profile
this module attaches.

## Exposing a service

`ingress_rules` opens **named** ports on that instance's own SG, scoped to the **VPC CIDR** — e.g. a
Prometheus box uses `ingress_rules = ["prometheus-http-tcp"]` (9090). Rule names come from the
security-group module's [predefined set](https://github.com/terraform-aws-modules/terraform-aws-security-group#available-rules)
(`grafana-tcp`, `https-443-tcp`, …), so you reference a service by name and the port is baked in.

This is for **east-west** (in-VPC) reachability only — public exposure is the **consuming
environment's** job (e.g. a Cloudflare Tunnel or reverse proxy run via `user_data`), so this module
stays cloud- and tool-agnostic. A box that only needs SSM keeps `ingress_rules = []` (egress-only).

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
| `ami`               | `""`        | Literal AMI id (wins if set). Empty → resolve via `ami_ssm_parameter`.       |
| `ami_ssm_parameter` | `""`        | Public SSM parameter tracking the latest image for an OS, resolved per-region. Empty → latest Amazon Linux 2023. E.g. Ubuntu 26.04: `/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id`. |
| `root_disk_size_gb` | `20`        | Root EBS volume size in GB.                                                  |
| `assign_public_ip`  | `false`     | Attach a public IP. Leave `false` for the SSM-only model.                    |
| `user_data`         | `""`        | First-boot script (userdata). Empty = no bootstrap. Supplied by the env.    |
| `ingress_rules`     | `[]`        | Named SG ingress rules to open on this instance (e.g. `["prometheus-http-tcp"]`), reachable from the VPC CIDR only. Empty = SSM-only, no inbound. |
| `iam_role_policy_arns` | `{}`     | Extra IAM policy ARNs to attach to this instance's role, keyed by a **static** name (e.g. `{ tunnel = aws_iam_policy.x.arn }`). Merged **on top of** the always-on `AmazonSSMManagedInstanceCore`, so SSM access is never lost. The component stays generic — it attaches whatever you pass; the **consumer composes the scoped policy** (e.g. read one SSM SecureString param + `kms:Decrypt`). Keys must be literals (`for_each`); ARN values may be computed. |

> **No `access_members`:** Session Manager access is an IAM concern on the *caller's* side
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
