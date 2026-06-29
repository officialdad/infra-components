#!/usr/bin/env bash
# One-time (idempotent) git-hook setup for this clone. Run once after cloning; Claude Code runs it
# automatically on SessionStart (see .claude/hooks/session-truth.sh). Installs:
#   - pre-commit + commit-msg via the pre-commit framework (fmt / validate / tflint, Conventional
#     Commits) -- skippable only with --no-verify, which tf-guard denies for Claude.
#   - a native pre-push tag guard (scripts/check-release-tag.sh): blocks pushing a vX.Y.Z tag whose
#     version isn't promoted in CHANGELOG.md. The framework can't do this -- it never sees tag refs.
set -uo pipefail
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "setup-hooks: not in a git repo" >&2; exit 1; }

rc=0
if command -v pre-commit >/dev/null 2>&1 && [ -f "$root/.pre-commit-config.yaml" ]; then
  ( cd "$root" && pre-commit install ) || rc=1
else
  echo "setup-hooks: pre-commit not found -- install it (pipx install pre-commit) for the fmt/validate/commit-msg gates" >&2
  rc=1
fi

# Native pre-push hook -- a thin wrapper so edits to the tracked guard take effect with no re-install.
hooks_dir="$(cd "$root" && git rev-parse --git-path hooks)"
case "$hooks_dir" in /*) ;; *) hooks_dir="$root/$hooks_dir" ;; esac
mkdir -p "$hooks_dir"
hook="$hooks_dir/pre-push"
if grep -q 'check-release-tag.sh' "$hook" 2>/dev/null; then
  : # already ours
elif [ -e "$hook" ]; then
  echo "setup-hooks: $hook exists and isn't ours -- not clobbering. Add this line to keep the release guard:" >&2
  echo '  exec "$(git rev-parse --show-toplevel)/scripts/check-release-tag.sh" "$@"' >&2
  rc=1
else
  cat >"$hook" <<'SH'
#!/usr/bin/env sh
# Installed by scripts/setup-hooks.sh -- delegates to the tracked guard so edits need no re-install.
exec "$(git rev-parse --show-toplevel)/scripts/check-release-tag.sh" "$@"
SH
  chmod +x "$hook"
  echo "setup-hooks: installed pre-push tag guard"
fi

exit $rc
