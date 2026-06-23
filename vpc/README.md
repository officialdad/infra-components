# vpc

Network foundation component (**AWS**): a VPC with **per-AZ** public and private subnets and a
single NAT gateway giving the private subnets outbound internet.

This component is a **thin wrapper** over the verified community module
[`terraform-aws-modules/vpc/aws`](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws) —
it manages no raw `aws_vpc` / `aws_subnet` resources itself. It bakes in *our* opinions (subnet
fan-out, single NAT, the `global` convention) so the environments repos consume a small, stable
interface and never see the upstream module's full input surface.

| Wraps | Version | Provides |
| ----- | ------- | -------- |
| [`terraform-aws-modules/vpc/aws`](https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws) | `~> 6.0` | VPC + per-AZ public/private subnets + route tables + NAT gateway |

## What it creates

- A **VPC** (`cidr_block`, default `10.0.0.0/16`) with DNS support and hostnames enabled.
- **Per-AZ private and public subnets** across the first `az_count` (default `2`) availability zones
  in the region. Each subnet is a `/20` carved from the VPC CIDR with `cidrsubnet(cidr, 4, i)`
  (private first, then public).
- A **single NAT gateway** — only when `enable_nat_gateway` (default `true`). Gives the private
  (no-public-IP) instances egress, including reaching AWS Systems Manager (SSM). This is the one
  piece that costs money at idle — set `enable_nat_gateway = false` to stop charges. *Single* NAT
  (not one per AZ) keeps it cheap; fine for non-prod.

The instance-facing security and access model (egress-only SG, SSM Session Manager) lives in the
**`ec2`** component, not here.

## Auth

The provider needs AWS credentials (env vars, shared config, or an instance/CI role) — supplied
out-of-band, none stored in this component. Region comes from `var.global.deploy_region`.

## Inputs

| Name                 | Type   | Default       | Description                                                                 |
| -------------------- | ------ | ------------- | --------------------------------------------------------------------------- |
| `global`             | object | —             | Env-wide context (`environment_name`, `deploy_region`, `tags`).             |
| `cidr_block`         | string | `10.0.0.0/16` | Primary IPv4 CIDR of the VPC.                                               |
| `az_count`           | number | `2`           | Number of AZs to spread private/public subnets across.                      |
| `enable_nat_gateway` | bool   | `true`        | Create a single NAT gateway so private instances get egress (incl. SSM).    |

## Outputs

| Name                 | Description                                                       |
| -------------------- | ---------------------------------------------------------------- |
| `vpc_id`             | The VPC id (pass to `ec2.vpc_id`).                               |
| `private_subnet_ids` | Private subnet ids (pass `ec2.subnet_id = private_subnet_ids[0]`). |
| `public_subnet_ids`  | Public subnet ids.                                               |
| `region`             | The region the VPC lives in.                                    |

Consumed by `ec2` (`vpc_id` → `vpc_id`, `private_subnet_ids[0]` → `subnet_id`).
