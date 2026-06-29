#!/usr/bin/env bash
# Generate each component README's Inputs/Outputs tables from its terraform/ module, injected between
# the <!-- BEGIN_TF_DOCS --> / <!-- END_TF_DOCS --> markers (config: .terraform-docs.yml). One script,
# three callers: pre-commit, CI, and the PostToolUse Claude hook (.claude/hooks/tf-docs.sh).
# Graceful when terraform-docs is absent (warns, exits 0) so local commits/agents aren't blocked --
# CI installs the binary, so the --check there is the authoritative gate.
#
# Usage: scripts/gen-docs.sh [--check] [component ...]
#   --check     don't write; exit 1 if any README is stale (the CI gate).
#   component   limit to these components (default: every README that has the markers).
set -uo pipefail
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "gen-docs: not in a git repo" >&2; exit 1; }
cd "$root"

check=0
comps=()
for a in "$@"; do
  case "$a" in
    --check) check=1 ;;
    *) comps+=("${a%/}") ;;
  esac
done

if ! command -v terraform-docs >/dev/null 2>&1; then
  echo "gen-docs: terraform-docs not installed -- skipping README generation (CI enforces it)." >&2
  echo "          install: https://terraform-docs.io/user-guide/installation/" >&2
  exit 0
fi

# Default set: every top-level <component>/terraform whose README carries the markers. (Iterating
# */terraform — not a recursive grep — avoids vendored .terraform/modules READMEs and the root README.)
if [ "${#comps[@]}" -eq 0 ]; then
  shopt -s nullglob
  for mod in */terraform; do
    c="${mod%/terraform}"
    grep -q 'BEGIN_TF_DOCS' "$c/README.md" 2>/dev/null && comps+=("$c")
  done
fi
[ "${#comps[@]}" -gt 0 ] || { echo "gen-docs: no component READMEs with TF_DOCS markers found." >&2; exit 0; }

rc=0
for c in "${comps[@]}"; do
  mod="$c/terraform"
  readme="$c/README.md"
  [ -d "$mod" ] || { echo "gen-docs: $mod not found, skipping" >&2; continue; }
  grep -q 'BEGIN_TF_DOCS' "$readme" 2>/dev/null \
    || { echo "gen-docs: $readme has no TF_DOCS markers, skipping" >&2; continue; }
  if [ "$check" -eq 1 ]; then
    terraform-docs --config "$root/.terraform-docs.yml" --output-check "$mod" >/dev/null 2>&1 \
      || { echo "gen-docs: $readme is OUT OF DATE -- run: scripts/gen-docs.sh" >&2; rc=1; }
  else
    terraform-docs --config "$root/.terraform-docs.yml" "$mod" >/dev/null && echo "gen-docs: updated $readme"
  fi
done
exit $rc
