# iam-policy

**Caller-composed AWS IAM managed policies** — the consumer authors each policy document (JSON) and
this component wraps it into a named, tagged `aws_iam_policy` and outputs its ARN. It models **no**
policy semantics of its own: it is the IaC home for IAM policies, so the environment can attach
scoped grants (e.g. onto an `ec2` instance role via `iam_role_policy_arns`) without writing raw
resources in the environments repo.

## What it creates

- **`aws_iam_policy` per `policies` entry** — named `<environment_name>-<key>`, body taken verbatim
  from that entry's `policy_json`, tagged with `common_tags`. Its ARN is returned in the
  `policy_arns` output under the same map key.

> ⚠️ **The document is yours to scope** — this component does not constrain actions or resources.
> Author least-privilege JSON (scope to specific ARNs; gate `kms:Decrypt` with a `kms:ViaService`
> condition) — a too-broad document becomes a too-broad policy.

## Auth

Provider needs AWS credentials (env vars / shared config / CI role) — supplied out-of-band, none
stored here. Region comes from `var.global.deploy_region`. The principal running `apply` needs
`iam:CreatePolicy` (and lifecycle siblings) on `policy/<environment_name>-*`.

## Dependencies

None. This is a leaf component — the environment composes each `policy_json` and consumes
`policy_arns` downstream (e.g. into `ec2`'s `iam_role_policy_arns`).

### `policies` entry shape

The generated Inputs table renders `policies` as one `map(object({…}))`. Per-field intent:

- `policy_json` (required) — the full IAM policy document as a JSON string. Author it with
  `jsonencode({ Version = "2012-10-17", Statement = [...] })` in the consuming environment, so the
  policy lives there; a new or changed grant is an edit on the consumer, never a component release.
- `description` (`""`) — optional policy description; empty falls back to a generated default.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| global | Environment-wide context injected by the environments repo (name, region, tags). | <pre>object({<br/>    environment_name = string<br/>    deploy_region    = string<br/>    tags             = map(string)<br/>  })</pre> | n/a | yes |
| policies | IAM managed policies keyed by short name; each entry's policy\_json is the full IAM policy document (the consumer composes it). Policy name = "<environment\_name>-<key>". Feed policy\_arns[<key>] into a consumer role (e.g. ec2 iam\_role\_policy\_arns). | <pre>map(object({<br/>    policy_json = string<br/>    description = optional(string, "")<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| policy\_arns | Managed policy ARNs keyed by their policies-map key. Feed an entry into a consumer role, e.g. ec2 iam\_role\_policy\_arns. |
<!-- END_TF_DOCS -->
