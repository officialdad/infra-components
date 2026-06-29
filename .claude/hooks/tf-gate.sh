#!/usr/bin/env bash
# Stop / SubagentStop quality gate.
# Runs fmt-check + validate + tflint on every component with UNCOMMITTED Terraform
# changes, and BLOCKS the turn from ending while anything is red. Degrades gracefully:
# a missing tool or no-network init is a warning, never a block (so the gate can't trap
# a teammate in an unfixable loop). Hook JSON arrives on stdin (unused).
set -uo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$root" || exit 0

# Files with uncommitted TF changes (staged, unstaged, untracked); $NF = new path on renames.
files="$(git status --porcelain | awk '{print $NF}' | grep -E '\.(tf|tfvars|tftest\.hcl)$' || true)"
[ -z "$files" ] && exit 0 # no Terraform changes → nothing to gate

# Map changed files to their component dirs (those holding versions.tf or main.tf).
comps="$(while IFS= read -r f; do [ -n "$f" ] && dirname "$f"; done <<<"$files" | sort -u)"
sel=""
while IFS= read -r d; do
  [ -z "$d" ] && continue
  { [ -f "$d/versions.tf" ] || [ -f "$d/main.tf" ]; } && sel+="$d"$'\n'
done <<<"$comps"
sel="$(printf '%s' "$sel" | sed '/^$/d')"
[ -z "$sel" ] && exit 0

if ! command -v terraform >/dev/null 2>&1; then
  jq -n '{systemMessage:"⚠ Terraform gate skipped: terraform not installed."}'
  exit 0
fi
have_tflint=0
command -v tflint >/dev/null 2>&1 && have_tflint=1

fail=""
warn=""
while IFS= read -r d; do
  [ -z "$d" ] && continue

  # fmt — no external deps, always enforced.
  if ! terraform -chdir="$d" fmt -check -recursive >/dev/null 2>&1; then
    fail+=$'\n'"  • $d: 'terraform fmt -check' failed — run: terraform -chdir=$d fmt -recursive"
  fi

  # validate — needs provider init; an init failure (offline / providers unavailable) is a warning.
  if terraform -chdir="$d" init -backend=false -input=false >/dev/null 2>&1; then
    if ! out="$(terraform -chdir="$d" validate -no-color 2>&1)"; then
      fail+=$'\n'"  • $d: 'terraform validate' failed:"$'\n'"$(printf '%s' "$out" | sed 's/^/      /')"
    fi
  else
    warn+=$'\n'"  • $d: could not init/validate (offline or providers unavailable) — fmt still checked."
  fi

  # tflint — only if installed.
  if [ "$have_tflint" -eq 1 ]; then
    tfout="$( (cd "$d" && tflint --init >/dev/null 2>&1; tflint --config="$root/.tflint.hcl" 2>&1) )" \
      || fail+=$'\n'"  • $d: tflint failed:"$'\n'"$(printf '%s' "$tfout" | sed 's/^/      /')"
  fi
done <<<"$sel"

if [ -n "$fail" ]; then
  reason="Terraform quality gate FAILED — fix before finishing:${fail}"
  [ -n "$warn" ] && reason+=$'\n'"Warnings:${warn}"
  jq -n --arg r "$reason" '{decision:"block",reason:$r}'
  exit 0
fi
if [ -n "$warn" ]; then
  jq -n --arg r "Terraform gate passed (fmt ok).${warn}" '{systemMessage:$r}'
fi
exit 0
