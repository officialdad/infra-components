#!/usr/bin/env bash
# PreToolUse (Bash): make Claude's `gh pr create` / `gh issue create` follow the repo
# templates. `gh ... --body "…"` bypasses the template prompt, so this checks the body
# carries the template's structure and denies (with guidance) if it doesn't. Humans using
# the web UI / interactive gh get the template natively — this only governs the agent.
# Hook JSON on stdin.
set -uo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}
has() { printf '%s' "$cmd" | grep -q "$1"; }

# --- Pull requests -------------------------------------------------------------------
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])gh[[:space:]]+pr[[:space:]]+create\b'; then
  # OK if the body is the filled template (inline sections present) or the template file.
  if { has '## Summary' && has '## Validation'; } || has 'pull_request_template.md'; then
    exit 0
  fi
  deny "PRs must follow the repo template. Either pass --body-file .github/pull_request_template.md (filled in), or include its sections in --body: '## Summary', '## Component(s)', '## Type', '## Changes', '## Validation'. Do not use --fill or a free-form body. See .github/pull_request_template.md."
fi

# --- Issues --------------------------------------------------------------------------
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])gh[[:space:]]+issue[[:space:]]+create\b'; then
  # OK if a template is selected, the template dir is referenced, or the marker is inline.
  if has 'ISSUE_TEMPLATE' || printf '%s' "$cmd" | grep -Eq '(--template|[[:space:]]-T[[:space:]])' || has '\*\*Component'; then
    exit 0
  fi
  deny "Issues must use a template. Pass --template module-bug.md (or module-change.md), or include the template body starting with '**Component(s)**'. See .github/ISSUE_TEMPLATE/."
fi

exit 0
