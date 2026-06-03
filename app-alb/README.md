# app-alb

A public Application Load Balancer with a security group, a target group, and an HTTP listener.
Mirrors the "ingress / ALB" role from the reference setup.

## Inputs

| Name                | Type         | Default    | Description                                  |
| ------------------- | ------------ | ---------- | -------------------------------------------- |
| `global`            | object       | —          | Env-wide context.                            |
| `vpc_id`            | string       | —          | VPC for the ALB and target group.            |
| `public_subnet_ids` | list(string) | —          | Public subnets to attach the ALB to.         |
| `target_port`       | number       | `8080`     | Target group forwarding port.                |
| `health_check_path` | string       | `/health`  | Health check path.                           |
| `internal`          | bool         | `false`    | Internal vs internet-facing.                 |

## Outputs

| Name                | Description                    |
| ------------------- | ------------------------------ |
| `alb_arn`           | Load balancer ARN.             |
| `alb_dns_name`      | Load balancer DNS name.        |
| `target_group_arn`  | Default target group ARN.      |
| `security_group_id` | Load balancer security group.  |

Depends on `vpc` for `vpc_id` and `public_subnet_ids` (public).
