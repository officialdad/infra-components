#!/usr/bin/env bash
# PostToolUse (Edit|Write|MultiEdit): canonical-format the edited Terraform file and
# steer the model to ground Terraform facts against the `terraform` MCP server.
# Non-blocking — always exits 0. Hook JSON arrives on stdin.
set -uo pipefail

input="$(cat)"
f="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -z "$f" ] && exit 0

case "$f" in
  *.tf | *.tfvars | *.tftest.hcl) ;;
  *) exit 0 ;; # not a Terraform file — nothing to do
esac

# terraform fmt accepts a single file target; format just the edited file.
if command -v terraform >/dev/null 2>&1 && [ -f "$f" ]; then
  terraform fmt "$f" >/dev/null 2>&1 || true
fi

# Inject grounding guidance back into the model's context (deterministic, every TF write).
jq -n '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: "Terraform file edited. Verify every provider/resource/data-source/module argument against the `terraform` MCP server (mcp__terraform__*) — HashiCorp'"'"'s authoritative source — not from memory and not via context7 (context7 is not the Terraform source here). The Stop gate will run fmt-check/validate/tflint on changed components before this turn can end; fix any failures."
  }
}'
exit 0
