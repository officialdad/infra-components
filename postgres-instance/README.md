# postgres-instance

An RDS PostgreSQL instance with a dedicated subnet group and security group. The master
password is generated with `random_password` and exposed as a **sensitive** output (in a real
setup you'd store it in AWS Secrets Manager or Vault, as the reference component does).

## Inputs

| Name                      | Type         | Default        | Description                              |
| ------------------------- | ------------ | -------------- | ---------------------------------------- |
| `global`                  | object       | —              | Env-wide context.                        |
| `database_identifier`     | string       | —              | Instance identifier (e.g. `app`).        |
| `subnet_ids`              | list(string) | —              | DB subnet group subnets (private).       |
| `vpc_id`                  | string       | —              | VPC for the security group.              |
| `database_instance_class` | string       | `db.t3.micro`  | RDS instance class.                      |
| `allocated_storage`       | number       | `20`           | Storage in GB.                           |
| `engine_version`          | string       | `16.3`         | PostgreSQL version.                      |
| `database_name`           | string       | `appdb`        | Initial database name.                   |
| `database_username`       | string       | `appadmin`     | Master username.                         |
| `multi_az`                | bool         | `false`        | Multi-AZ deployment.                     |

## Outputs

| Name                | Sensitive | Description                       |
| ------------------- | --------- | --------------------------------- |
| `database_address`  | no        | RDS hostname.                     |
| `database_endpoint` | no        | host:port.                        |
| `database_arn`      | no        | Instance ARN.                     |
| `security_group_id` | no        | DB security group ID.             |
| `database_username` | no        | Master username.                  |
| `database_password` | **yes**   | Generated master password.        |

Depends on `vpc` for `subnet_ids` (private) and `vpc_id`.
