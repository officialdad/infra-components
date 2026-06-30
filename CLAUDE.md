# CLAUDE.md

Guidance for working in `infra-components`. Read this before adding or changing a component.
Authoritative human docs: **[README.md](./README.md)** (overview + the conventions contract) and
**[CHANGELOG.md](./CHANGELOG.md)** (per-version history).
When code and these docs disagree, that's a bug — fix both in the same change.

## What this repo is

A **reusable Terraform module library**, not a deployment. Each top-level directory is a
**component**; its Terraform lives in `<component>/terraform/`. The environments repos consume
components by pinned git source:

```hcl
terraform { source = "git::https://github.com/officialdad/infra-components.git//<component>/terraform?ref=<tag>" }
```

- `infra-environments-dev` tracks `main`; `infra-environments-prod` pins `vX.Y.Z` tags.
- Nothing is **applied** here. CI only `fmt` / `validate` / `tflint`s each component with the
  backend disabled and **no cloud credentials**. Keep every component greenfield-plannable (no live
  data-source lookups that require real infra to exist — pass values through inputs instead; see how
  `ec2` takes `vpc_cidr` as an input rather than an `aws_vpc` lookup).

## Components

Dual-stack on purpose — an environment picks a cloud. Two parallel foundation→compute chains:

| Component | Cloud | Role |
| --- | --- | --- |
| `vpc` → `ec2` | AWS | network foundation → EC2 instances (SSM access) |
| `network` → `compute-engine` | GCP | network foundation → Compute Engine VMs (OS Login + IAP) |
| `automation-roles` | AWS | GitHub-OIDC → IAM CI role (human-applied, off-pipeline) |
| `github` | GitHub | repository factory (org-scoped) |

## Module anatomy (every component)

```text
<component>/
├── README.md          # inputs/outputs tables, auth, dependencies
└── terraform/
    ├── versions.tf    # required_version (>= 1.5.7) + required_providers (~> pins)
    ├── variables.tf   # inputs; `global` is the first variable (except github)
    ├── main.tf        # provider block + resources
    └── outputs.tf     # values consumed downstream
```

## The conventions that must hold

These are the contract the environments repos rely on. Keep them identical across components.

- **`global` first.** Every component takes `global = { environment_name, deploy_region, tags }` as
  its first variable. **Exception: `github`** (org-scoped, nothing to tag — a dead `global` would
  trip `tflint`'s unused-declaration rule). If you add another genuinely env-less component,
  document the exception in README.md + the component README, don't add a dead variable.
- **Tags / labels on everything taggable.**
  - AWS: `merge(var.global.tags, { ManagedBy = "terraform", Environment = var.global.environment_name })`
    via a `common_tags` local, applied to every resource.
  - GCP: `global.tags` is **sanitized** into labels (lowercase, chars outside `[a-z0-9_-]` → `_`) on
    resources that support labels (e.g. the `compute-engine` instance). GCP **networking** resources
    (network, subnet, router, NAT, firewall) **cannot** be labeled — naming carries env there.
- **Naming is deterministic, no random suffixes.** Resources: `<environment_name>-<component>[-<purpose>]`.
  Instances in a map: `<environment_name>-<key>`.
- **Version pins.** `required_version = ">= 1.5.7"` everywhere. Provider versions use bounded `~>`
  pins (e.g. `~> 6.0`). Only raise a floor when a wrapped module forces it, and add a comment
  saying why (see `ec2/terraform/versions.tf`).
- **`instances` map + `for_each`** is the pattern for "one or more of a thing." Adding one is a map
  entry on the consumer side; per-entry fields are `optional(...)` with safe defaults. Validate map
  keys (RFC1035-style regex) so bad names fail at plan, loudly.

## Design principles (KISS, but ready to scale)

- **Thin wrappers over verified registry modules** where one exists (`terraform-aws-modules/*`,
  `terraform-google-modules/*`). Bake in *our* opinions and expose a small, stable interface — the
  environments repos should never see the upstream module's full input surface. Write raw resources
  only when no good module exists (e.g. `automation-roles` IAM).
- **Required inputs = identity/placement only** (`project_id`, `vpc_id`, `subnet_id`) — no safe
  default, must fail loudly when unset. **Defaulted inputs = the cost-safe "how"** (`t3.micro`,
  20 GB, `debian-12`) — harmless when forgotten.
- **Bootstrap-agnostic.** Modules run caller-supplied `user_data` / `startup_script` (`""` = none);
  they never bake in what to install. The consuming environment owns bootstrap.
- **Secure defaults:** no public IP, egress/identity-based access (SSM / IAP+OS Login), encrypted
  root disks, least-privilege IAM, IMDSv2. A consumer opts *into* exposure, never out of it.
- Don't add a knob until a real consumer needs it. Prefer a new `optional` field over a new variable.

## Providers — important constraint

Each component declares a **configured `provider` block** in `main.tf` (region/project from
`var.global.deploy_region`). This is valid **because components are consumed as Terragrunt *root*
modules**. Do **not** call a component as a native child `module "x" { source = ".../terraform" }` —
a configured provider inside a child module breaks `for_each`/`count`/aliased providers and emits
deprecation warnings. `versions.tf` carries only `required_providers`.

## Duplication is deliberate

The `variable "global"` block, the `common_tags` local, and the `instances`-key validation regex are
**duplicated verbatim** across components. Sibling root modules can't share locals without an
internal submodule, and that indirection isn't worth saving a few lines. **When you change one of
these blocks, mirror the change across every component identically** — they are a de-facto shared
interface even though the tooling can't enforce it.

## Component README style

Each `<component>/README.md` is scaffolded from `.github/component-readme-template.md` and follows one
house voice (exemplars: **`vpc`**, **`ec2`**). The point is a *deterministic shape*, not freehand
prose — **structure** and **format** are enforced in CI; **voice** is a contract you follow:

- **Title + one lead sentence** — what it is, which cloud, the single defining opinion. Stop there.
- **`## What it creates`** — a bullet list. Bold the resource/noun, then a concise clause; defaults in
  `backticks`. Sharp edges go in a `> ⚠️` blockquote, never inline prose.
- **Active voice, one idea per bullet** — lead with the thing, cut filler ("This component is…"). If a
  sentence can be a bullet, make it one.
- **`## Auth`** — 1–3 lines: which credentials, supplied out-of-band, where region/project comes from.
- **`## Dependencies`** (required) — bullets mapping upstream outputs → this component's inputs;
  `None.` for a foundation.
- **`## Inputs` / `## Outputs`** — **generated** by terraform-docs between the `<!-- BEGIN_TF_DOCS -->`
  / `<!-- END_TF_DOCS -->` markers; **never hand-edit**. For a `map`/`object` input (`instances`,
  `repositories`), add a short prose **"entry shape"** explainer above the block — the generated table
  is the authoritative reference, the prose explains the per-field intent the collapsed type can't.

Mechanics (enforced): `scripts/gen-docs.sh` regenerates the tables (pre-commit + CI `--check`);
`scripts/check-readme-structure.sh` asserts the required sections + markers; `markdownlint` enforces
formatting. The `/component-readme` skill writes to this spec.

## Checklist — adding or changing a component

- [ ] `terraform/` with `versions.tf` / `variables.tf` / `main.tf` / `outputs.tf`
- [ ] `global` as first variable (or a documented exception)
- [ ] `common_tags` (AWS) or sanitized labels (GCP) on every taggable resource
- [ ] `required_version = ">= 1.5.7"`; bounded `~>` provider pins
- [ ] `README.md` from `.github/component-readme-template.md`: lead sentence, **What it creates**, **Auth**, **Dependencies**, and the `<!-- BEGIN/END_TF_DOCS -->` markers — Inputs/Outputs are **generated** (`scripts/gen-docs.sh`), never hand-written. Follow [Component README style](#component-readme-style)
- [ ] CI validates it automatically — the `.github/workflows/ci.yml` matrix is **derived from the filesystem** (any `<component>/terraform/` dir), so there's no matrix list to edit; just confirm the `discover` job picks it up
- [ ] Add a row to the **root README** components table
- [ ] Write a **consumer-facing commit subject** — `type(scope): subject`, scope = component; flag input/output/breaking (`!` / `BREAKING CHANGE:`). The CHANGELOG is **generated** from these commits at release time (no hand-edited `[Unreleased]` — `scripts/release.sh` runs git-cliff)
- [ ] If a change touches inputs/outputs, update README.md / the component README in the same commit

## Automated gate & grounding (committed, team-wide)

This repo ships a deterministic quality layer in `.claude/settings.json` + `.claude/hooks/` —
the *harness* runs these regardless of the model, so quality and truth are enforced, not hoped for:

- **Auto-format** — every `*.tf` edit is `terraform fmt`'d immediately (`tf-postwrite.sh`).
- **Auto-docs** — after a `*.tf` edit, `tf-docs.sh` regenerates that component's README Inputs/Outputs
  tables (terraform-docs). pre-commit + CI then enforce the tables, README structure, and markdown
  style (`scripts/gen-docs.sh --check`, `check-readme-structure.sh`, `markdownlint`) — docs can't drift.
- **Blocking finish gate** — on Stop/SubagentStop, `tf-gate.sh` runs `fmt -check` + `validate` +
  `tflint` on components with *uncommitted* Terraform changes and **blocks the turn from ending
  while anything is red**. `validate` is a schema oracle: you cannot finish with a hallucinated
  resource/argument. Missing tool or offline init degrades to a warning, never a false block.
- **Hard guardrails** — `tf-guard.sh` denies `terraform/tofu apply|destroy` (apply lives in the
  environments repos) and any `git --no-verify` / `commit -n` (which would skip the pre-commit
  fmt + secret-detection gate). Don't try to route around these.
- **Session truth banner** — `session-truth.sh` prints real toolchain/branch state at start.
- **PR/issue format** — `gh-format-guard.sh` denies `gh pr/issue create` whose body doesn't follow
  the repo templates. When opening a PR, fill **`.github/pull_request_template.md`** (pass it via
  `--body-file`, or include its `## Summary … ## Validation` sections) — don't `--fill` or free-form.
  For issues, use `--template module-bug.md` or `module-change.md`.

**Grounding Terraform facts:** a project MCP server `terraform`
(`hashicorp/terraform-mcp-server`, see `.mcp.json`) is the **authoritative source** for provider /
resource / data-source / module schema and registry lookups. Use its tools (`mcp__terraform__*`)
when you need to confirm Terraform syntax — **not memory, and not context7** (context7 is not the
Terraform source in this repo). First use pulls the Docker image.

## Validate before you commit

```bash
pre-commit run --all-files          # fmt, validate, tflint, secret/merge-conflict checks
# or per component:
terraform -chdir=<component>/terraform fmt -check -recursive
terraform -chdir=<component>/terraform init -backend=false -input=false
terraform -chdir=<component>/terraform validate
```

`tflint` uses the **recommended** preset (`.tflint.hcl`) — it flags unused declarations, so don't
leave dead variables/locals/outputs. Don't commit `.terraform/`, lock files, or state (`.gitignore`
covers them).

**Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/)** —
`type(scope): subject` (`feat(ec2): …`, `fix(vpc): …`, `docs: …`; `!`/`BREAKING CHANGE:` for
breaking). Enforced on the `commit-msg` stage by `conventional-pre-commit`; `--no-verify` is denied
by `tf-guard.sh`, so write them right. Tagging stays manual (see README releasing).

## Releasing

Git tags `vMAJOR.MINOR.PATCH`, consumed via `?ref=<tag>`. MAJOR = breaking input/output change.
Tags are **repo-wide** (not per-component); each `//<component>/terraform?ref=<tag>` pin is fetched
independently, so an unchanged component validly stays at an older tag. Cut releases with
**`/release X.Y.Z`** (or `scripts/release.sh X.Y.Z`) — it **generates** the `## [X.Y.Z]` section from
the release's Conventional Commits with git-cliff (requires git-cliff locally — see README
"Toolchain"), splices it under `## [Unreleased]`, fixes the compare links, and commits + tags
**locally** (nothing pushed); review, then `git push origin main vX.Y.Z`. The changelog is generated,
never hand-curated; history ≤ `v0.6.0` is frozen. A native **`pre-push` guard**
(`scripts/check-release-tag.sh`, installed by `scripts/setup-hooks.sh`) blocks a tag push whose
`## [X.Y.Z] - <date>` section is missing from the CHANGELOG. The tag push publishes the GitHub Release
from the same git-cliff config (so it matches the CHANGELOG). Tagging stays manual and deliberate —
never auto-released on merge. Full steps in [README.md](./README.md#versioning--releasing).

## Guardrails

- **Placeholders only** — never commit real account IDs, credentials, hostnames, or thumbprints.
- Keep modules **valid and applyable** (real resource blocks), so environments can actually grow them.
- Credentials are supplied out-of-band by the environment (env vars / ADC / CI role); modules store none.
