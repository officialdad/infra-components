#!/usr/bin/env bash
# Assert every component README follows the canonical structure: the required section headers plus
# the terraform-docs markers. Pairs with .github/component-readme-template.md and scripts/gen-docs.sh.
# Run by pre-commit + CI. Catches a component shipping without a Dependencies section, or with a
# hand-written Inputs/Outputs table where the generated block belongs (no markers).
set -uo pipefail
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "check-readme: not in a git repo" >&2; exit 1; }
cd "$root"

# pattern -> human label (kept in lockstep)
patterns=('^# '              '^## What it creates' '^## Auth' '^## Dependencies' 'BEGIN_TF_DOCS'          'END_TF_DOCS')
labels=(  'H1 title'         '## What it creates'  '## Auth' '## Dependencies'  '<!-- BEGIN_TF_DOCS -->' '<!-- END_TF_DOCS -->')

rc=0
found=0
shopt -s nullglob
for mod in */terraform; do
  c="${mod%/terraform}"
  readme="$c/README.md"
  found=1
  if [ ! -f "$readme" ]; then
    echo "check-readme: $readme is missing" >&2
    rc=1
    continue
  fi
  miss=()
  for i in "${!patterns[@]}"; do
    grep -Eq "${patterns[$i]}" "$readme" || miss+=("${labels[$i]}")
  done
  if [ "${#miss[@]}" -gt 0 ]; then
    printf 'check-readme: %s missing: %s\n' "$readme" "$(IFS=' | '; echo "${miss[*]}")" >&2
    rc=1
  fi
done

[ "$found" -eq 1 ] || { echo "check-readme: no */terraform components found (run from repo root)" >&2; exit 1; }
[ "$rc" -eq 0 ] && echo "check-readme: all component READMEs follow the template"
exit $rc
