#!/usr/bin/env bash
# PostToolUse (Edit|Write|MultiEdit): after a component's *.tf changes, regenerate that component's
# README Inputs/Outputs tables (terraform-docs) so the docs never drift from the code. Mirrors how
# tf-postwrite.sh runs `terraform fmt`. No-op when the edited file isn't a component .tf, and
# gen-docs.sh itself is graceful when terraform-docs is absent. Hook JSON on stdin.
set -uo pipefail

input="$(cat)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)"
[ -z "$file" ] && exit 0
case "$file" in *.tf) ;; *) exit 0 ;; esac

root="$(git rev-parse --show-toplevel 2>/dev/null || echo "${CLAUDE_PROJECT_DIR:-.}")"
rel="${file#"$root"/}"                       # strip repo root if the path is absolute
case "$rel" in
  */terraform/*) comp="${rel%%/terraform/*}" ;;   # component = segment before /terraform/
  *) exit 0 ;;
esac
[ -d "$root/$comp/terraform" ] || exit 0

( cd "$root" && bash scripts/gen-docs.sh "$comp" >/dev/null 2>&1 ) || true
exit 0
