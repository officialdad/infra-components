# vpc

Network foundation component: a VPC with public and private subnets spread across
availability zones, an internet gateway, and public routing.

## Inputs

| Name                     | Type     | Default       | Description                                   |
| ------------------------ | -------- | ------------- | --------------------------------------------- |
| `global`                 | object   | —             | Env-wide context (environment_name, deploy_region, tags). |
| `cidr_block`             | string   | `10.0.0.0/16` | VPC CIDR block.                               |
| `az_count`               | number   | `3`           | Number of AZs (1–3).                          |
| `public_subnet_newbits`  | number   | `8`           | cidrsubnet newbits for public subnets.        |
| `private_subnet_newbits` | number   | `8`           | cidrsubnet newbits for private subnets.       |

## Outputs

| Name                      | Description                                          |
| ------------------------- | ---------------------------------------------------- |
| `vpc_id`                  | The VPC ID.                                          |
| `cidr_block`              | The VPC CIDR.                                        |
| `subnet_ids_list_by_name` | Map of tier → list of subnet IDs (`public`, `private`). |

Consumed by `postgres-instance` (private subnets) and `app-alb` (public subnets).
