#!/usr/bin/env bash
# PreToolUse (Bash): hard guardrails for this validate-only module library.
# Denies apply/destroy (those belong to the environments repos) and any attempt to
# bypass git hooks (--no-verify / commit -n, which would skip the fmt + secret checks).
# Hook JSON arrives on stdin.
set -uo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# terraform/tofu apply|destroy as a subcommand (tolerates global flags like -chdir=).
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])(terraform|tofu)[[:space:]]+([-][^[:space:]]+[[:space:]]+)*(apply|destroy)([[:space:]]|$)'; then
  deny "Denied: this is a validate-only module library — 'terraform/tofu apply|destroy' is not run here. Apply happens in the environments repos (infra-environments-dev/prod). Use 'plan'/'validate' instead."
fi

# Bypassing git hooks would skip the pre-commit fmt + secret-detection gate.
# --no-verify on commit/push, or a short-flag cluster containing -n right after `commit`
# (e.g. -n, -nm) — anchored to the first arg so a commit *message* mentioning "-n" is fine.
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])git([^&|;]*)(commit|push)([^&|;]*)--no-verify' \
  || printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])git([^&|;]*)commit[[:space:]]+-[a-zA-Z]*n[a-zA-Z]*([[:space:]]|$)'; then
  deny "Denied: refusing to bypass git hooks (--no-verify / -n). The pre-commit hooks run terraform fmt and secret detection. Fix the underlying issue instead of skipping the gate."
fi

exit 0
