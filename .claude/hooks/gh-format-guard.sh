#!/usr/bin/env bash
# PreToolUse (Bash): make Claude's `gh pr create` / `gh issue create` follow the repo
# templates. Checks the body — inline (--body) OR a --body-file's content — for the template's
# structure and denies with guidance if it's missing. Humans on the web UI / interactive gh get
# the template natively; this only governs the agent. Hook JSON on stdin.
set -uo pipefail

input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}
has() { printf '%s' "$cmd" | grep -q "$1"; } # marker present in the command string (inline body)

# If a --body-file / -F path is given, read it so a filled template passed by file is inspected,
# not just the command string.
bodyfile="$(printf '%s' "$cmd" | sed -nE 's/.*(--body-file|-F)[[:space:]=]+"?([^" ]+).*/\2/p' | head -1)"
bodytext=""
[ -n "$bodyfile" ] && [ -f "$bodyfile" ] && bodytext="$(cat "$bodyfile" 2>/dev/null)"
fhas() { [ -n "$bodytext" ] && printf '%s' "$bodytext" | grep -q "$1"; } # marker present in the body file

# --- Pull requests -------------------------------------------------------------------
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])gh[[:space:]]+pr[[:space:]]+create\b'; then
  if { has '## Summary' && has '## Validation'; } \
    || { fhas '## Summary' && fhas '## Validation'; } \
    || has 'pull_request_template.md'; then
    exit 0
  fi
  deny "PRs must follow the repo template. Pass --body-file .github/pull_request_template.md (filled), a --body-file whose content has the template sections, or include them in --body: '## Summary', '## Component(s)', '## Type', '## Changes', '## Validation'. Not --fill or a free-form body. See .github/pull_request_template.md."
fi

# --- Issues --------------------------------------------------------------------------
if printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]_])gh[[:space:]]+issue[[:space:]]+create\b'; then
  if has 'ISSUE_TEMPLATE' || printf '%s' "$cmd" | grep -Eq '(--template|[[:space:]]-T[[:space:]])' \
    || has '\*\*Component' || fhas '\*\*Component'; then
    exit 0
  fi
  deny "Issues must use a template. Pass --template module-bug.md (or module-change.md), or a body that starts with '**Component(s)**'. See .github/ISSUE_TEMPLATE/."
fi

exit 0
