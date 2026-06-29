# automation-roles

CI identity component (**AWS**): a **GitHub Actions → AWS OIDC** trust + an **IAM role** the
pipeline assumes with short-lived tokens — no static `AWS_*` access keys. This is the AWS analog
of the GCP WIF `automation-roles` work and unblocks the CI plan/apply for the `vpc` + `ec2`
components.

This component manages **raw IAM resources** (no upstream module): the OIDC provider, the role, its
trust policy, and a least-privilege permissions policy.

## What it creates

- An **`aws_iam_openid_connect_provider`** for `token.actions.githubusercontent.com`
  (`client_id_list = ["sts.amazonaws.com"]`). `thumbprint_list` is **omitted** — it is optional in
  the current AWS provider, which validates this provider against AWS's own CA store; a hardcoded
  thumbprint would only rot.
  > ⚠️ **The OIDC provider is an account-global singleton.** Only one per AWS account. If the
  > account already federates GitHub, set `create_oidc_provider = false` and pass
  > `existing_oidc_provider_arn` — otherwise apply fails with `EntityAlreadyExists`.
- An **`aws_iam_role`** CI assumes. Trust policy: `Federated` = the OIDC provider, audience
  `sts.amazonaws.com`, and `sub` restricted to `allowed_subjects`. **Default is ref/event-scoped**
  (the repo's `main` branch for apply + `pull_request` events for plan) — *not* a bare repo `:*`
  wildcard. Override `allowed_subjects` to change.
- An **`aws_iam_policy`** (least-privilege, first pass) attached to the role, granting only what
  `vpc` + `ec2` need: EC2/VPC (subnets, route tables, IGW, NAT, EIP, security groups, instances),
  IAM scoped to `<env>-*` roles/instance-profiles (for the `ec2` module's instance profile, incl.
  `PassRole`), and SSM read for public AMI parameters. No `AdministratorAccess`. Tighten iteratively
  from plan errors.

## Auth

**Human-applied, and excluded from the pipeline it bootstraps** (separation of duties). The
applier needs IAM-admin-ish credentials out-of-band — none are stored here. Region comes from
`var.global.deploy_region` (IAM is global; region only sets the provider endpoint).

## Inputs

| Name                         | Type         | Default                  | Description                                                                                  |
| ---------------------------- | ------------ | ------------------------ | -------------------------------------------------------------------------------------------- |
| `global`                     | object       | —                        | Env-wide context (`environment_name`, `deploy_region`, `tags`).                              |
| `github_org`                 | string       | `officialdad`            | Org/user owning the CI repo.                                                                  |
| `github_repo`                | string       | `infra-environments-dev` | Repo whose workflows assume the role.                                                         |
| `allowed_subjects`           | list(string) | `[]`                     | OIDC `sub` claims allowed (`StringLike`). Empty = `main` (apply) + `pull_request` (plan).     |
| `role_name`                  | string       | `""`                     | Role name. Empty = `"<environment_name>-github-actions-ci"`.                                  |
| `create_oidc_provider`       | bool         | `true`                   | Create the account-global GitHub OIDC provider. False = reference an existing one.            |
| `existing_oidc_provider_arn` | string       | `""`                     | Existing provider ARN. Required when `create_oidc_provider = false`.                          |
| `additional_policy_arns`     | list(string) | `[]`                     | Extra managed policy ARNs to attach on top of the built-in least-privilege policy.           |

## Outputs

| Name                | Description                                                                                     |
| ------------------- | ----------------------------------------------------------------------------------------------- |
| `role_arn`          | ARN of the CI role. Consumed by the env unit → repo secret `AWS_ROLE_ARN`.                      |
| `oidc_provider_arn` | ARN of the GitHub OIDC provider (created here, or the existing one passed in).                  |
| `role_name`         | Name of the CI role.                                                                            |

Consumed by the **infra-environments-dev** repo: `role_arn` → `AWS_ROLE_ARN` secret, used by
`aws-actions/configure-aws-credentials@v6` (with `permissions: id-token: write`) so the pipeline
assumes this role for `vpc`/`ec2` plan + apply.
