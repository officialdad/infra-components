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

## Dependencies

- **Upstream:** none — bootstraps the AWS CI identity from raw IAM (no module, no component inputs).
- **Consumed by `infra-environments-dev`:** `role_arn` → the `AWS_ROLE_ARN` secret, used by
  `aws-actions/configure-aws-credentials@v6` (with `permissions: id-token: write`) so the pipeline
  assumes this role for `vpc` / `ec2` plan + apply.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| global | Environment-wide context injected by the environments repo (name, region, tags). | <pre>object({<br/>    environment_name = string<br/>    deploy_region    = string<br/>    tags             = map(string)<br/>  })</pre> | n/a | yes |
| additional\_policy\_arns | Extra managed policy ARNs to attach to the role, on top of the built-in least-privilege policy. Keep this empty unless a unit genuinely needs more than vpc+ec2 require. | `list(string)` | `[]` | no |
| allowed\_subjects | OIDC `sub` claims allowed to assume the role (StringLike). Empty = the recommended ref/event-scoped default: the repo's main branch (apply) + pull\_request events (plan). Override to tighten or loosen, e.g. ["repo:org/repo:*"] for any ref. Never use a bare org/* wildcard. | `list(string)` | `[]` | no |
| create\_oidc\_provider | Create the account-global GitHub OIDC provider. Set false if the account already federates GitHub (token.actions.githubusercontent.com) and pass existing\_oidc\_provider\_arn instead. | `bool` | `true` | no |
| existing\_oidc\_provider\_arn | ARN of a pre-existing GitHub OIDC provider. Used (and required) only when create\_oidc\_provider = false. | `string` | `""` | no |
| github\_org | GitHub org/user that owns the CI repo allowed to assume the role. | `string` | `"officialdad"` | no |
| github\_repo | GitHub repo (within github\_org) whose Actions workflows assume the role. | `string` | `"infra-environments-dev"` | no |
| role\_name | Name of the IAM role CI assumes. Empty = "<environment\_name>-github-actions-ci". | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| oidc\_provider\_arn | ARN of the GitHub OIDC provider (created here, or the existing one passed in). |
| role\_arn | ARN of the CI role. Consumed by the env unit → repo secret AWS\_ROLE\_ARN (used by aws-actions/configure-aws-credentials). |
| role\_name | Name of the CI role. |
<!-- END_TF_DOCS -->
