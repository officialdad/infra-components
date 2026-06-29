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
  piece that costs money at idle. *Single* NAT (not one per AZ) keeps it cheap; fine for non-prod.
  > ⚠️ **`enable_nat_gateway = false` is not a free cost lever — it removes the only access path.**
  > Instances have no public IP and no inbound, and the SSM agent reaches the service by dialing
  > *out* through the NAT. With NAT off there is no egress *and* no ingress: the box is unreachable.
  > Only set `false` if you add SSM VPC interface endpoints (`ssm`, `ssmmessages`, `ec2messages`)
  > as the alternative path, or genuinely want an air-gapped instance.

The instance-facing security and access model (egress-only SG, SSM Session Manager) lives in the
**`ec2`** component, not here.

## Auth

The provider needs AWS credentials (env vars, shared config, or an instance/CI role) — supplied
out-of-band, none stored in this component. Region comes from `var.global.deploy_region`.

## Dependencies

- **Upstream:** none — `vpc` is a network foundation.
- **Consumed by `ec2`:** `vpc_id` → `vpc_id`, `vpc_cidr_block` → `vpc_cidr`,
  `private_subnet_ids[0]` → `subnet_id`.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| global | Environment-wide context injected by the environments repo (name, region, tags). | <pre>object({<br/>    environment_name = string<br/>    deploy_region    = string<br/>    tags             = map(string)<br/>  })</pre> | n/a | yes |
| az\_count | Number of AZs to spread private/public subnets across. | `number` | `2` | no |
| cidr\_block | Primary IPv4 CIDR of the VPC. | `string` | `"10.0.0.0/16"` | no |
| enable\_nat\_gateway | Create a single NAT gateway so private (no-public-IP) instances get egress, including reaching AWS Systems Manager (SSM). | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| private\_subnet\_ids | Private subnet ids (pass ec2.subnet\_id = private\_subnet\_ids[0]). |
| public\_subnet\_ids | Public subnet ids. |
| region | Region the VPC lives in. |
| vpc\_cidr\_block | The VPC CIDR (pass to ec2.vpc\_cidr for SG ingress). |
| vpc\_id | The VPC id (pass to ec2.vpc\_id). |
<!-- END_TF_DOCS -->
