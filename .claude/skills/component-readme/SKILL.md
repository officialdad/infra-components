---
name: component-readme
description: Write or update a component's README.md in the repo's house style — lead sentence, bulleted "What it creates", Auth, Dependencies, and terraform-docs-generated Inputs/Outputs. Use when creating a component or editing/standardizing a <component>/README.md.
---

# Write a component README

Produce a `<component>/README.md` in the one house voice (exemplars: `vpc`, `ec2`). Structure and
format are enforced by CI; this skill is how you get the *voice* right. Full spec: CLAUDE.md →
"Component README style".

## Scaffold
Start from `.github/component-readme-template.md` (copy it for a new component; for an existing one,
reshape to match it). Required sections, in order: title + lead sentence → `## What it creates` →
[optional narrative] → `## Auth` → `## Dependencies` → the `<!-- BEGIN_TF_DOCS -->` markers.

## The voice (match `vpc` / `ec2`)
- **Title + ONE lead sentence** — what it is, which cloud, the single defining opinion. No more.
- **`## What it creates`** — a bullet list. **Bold the resource/noun**, then a concise clause; defaults
  in `backticks`. Footguns → a `> ⚠️` blockquote, never inline prose.
- **Active voice, one idea per bullet.** Lead with the thing; cut "This component is…". If a sentence
  can be a bullet, make it one. Concise > complete — the generated tables carry the reference detail.
- **`## Auth`** — 1–3 lines: credentials, supplied out-of-band, region/project source.
- **`## Dependencies`** (required) — bullets mapping upstream outputs → this component's inputs;
  `None.` for a foundation.
- **Map/object inputs** (`instances`, `repositories`) — add a short prose **"entry shape"** explainer
  above the generated block; the generated table is the reference, the prose explains per-field intent.

## Never hand-write Inputs/Outputs
They are generated from `variables.tf` / `outputs.tf` between the markers. To fix a table cell, edit
the variable/output **`description`** in the `.tf` — not the README — then regenerate:

```bash
scripts/gen-docs.sh <component>     # the PostToolUse hook also runs this after a .tf edit
```

## Before finishing
```bash
scripts/check-readme-structure.sh              # required sections + markers present
scripts/gen-docs.sh --check                    # tables up to date
npx markdownlint-cli2 "<component>/README.md"  # formatting (or let pre-commit/CI run it)
```
