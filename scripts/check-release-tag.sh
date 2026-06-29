#!/usr/bin/env bash
# Native git pre-push guard (installed into .git/hooks/pre-push by scripts/setup-hooks.sh).
# Reads the push refs on stdin; for every vX.Y.Z tag being pushed it refuses the push unless
# CHANGELOG.md already has a matching released section (`## [X.Y.Z] - <date>`). Catches the classic
# "tagged but forgot to promote the CHANGELOG" / "tag doesn't match" mistake -- for the whole team,
# not just the agent. The pre-commit framework can't do this (it's file-oriented and never sees the
# tag refs), so this is a native hook.
#
# Deliberate override: `git push --no-verify` (denied for Claude by .claude/hooks/tf-guard.sh).
set -uo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cl="$root/CHANGELOG.md"
status=0

# stdin: <local_ref> <local_oid> <remote_ref> <remote_oid>  (one line per ref being pushed)
while read -r local_ref local_oid _remote_ref _remote_oid; do
  case "$local_ref" in
    refs/tags/v[0-9]*) ;;
    *) continue ;;
  esac
  # Deleting a tag (local_oid all zeros) -- nothing to validate.
  case "$local_oid" in *[!0]*) ;; *) continue ;; esac

  tag="${local_ref#refs/tags/}"   # vX.Y.Z
  num="${tag#v}"                  # X.Y.Z
  printf '%s' "$num" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || continue  # only semver release tags

  esc="$(printf '%s' "$num" | sed 's/\./\\./g')"
  if [ -f "$cl" ] && grep -Eq "^## \[$esc\] - " "$cl"; then
    continue
  fi
  printf 'pre-push: refusing to push tag %s -- CHANGELOG.md has no "## [%s] - <date>" section.\n' "$tag" "$num" >&2
  printf '          Promote [Unreleased] first:  scripts/release.sh %s   (or the /release skill).\n' "$num" >&2
  printf '          Deliberately overriding?     git push --no-verify    (not available to Claude).\n' >&2
  status=1
done

exit $status
