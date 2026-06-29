#!/usr/bin/env bash
# Cut a release: promote CHANGELOG [Unreleased] -> `## [X.Y.Z] - <today>`, fix the two compare
# links, then commit `chore(release): vX.Y.Z` and tag `vX.Y.Z` -- LOCALLY. Nothing is pushed.
# Review with `git show vX.Y.Z`; publish with `git push origin main vX.Y.Z` (a pre-push guard
# checks the tag matches the CHANGELOG). Undo before pushing:
#   git tag -d vX.Y.Z && git reset --hard HEAD~1
#
# The promotion is pure text surgery on your hand-curated [Unreleased] -- it does NOT regenerate
# from git-cliff, so curation is preserved (git-cliff only drafts the PR-comment previews).
#
# Usage: scripts/release.sh X.Y.Z [--dry-run]
#   --dry-run  print the CHANGELOG diff only; touch nothing, skip all git-state checks.
set -euo pipefail

die() { printf 'release: %s\n' "$1" >&2; exit 1; }

ver="${1:-}"
dry=0
[ "${2:-}" = "--dry-run" ] && dry=1
[ -n "$ver" ] || die "usage: scripts/release.sh X.Y.Z [--dry-run]"
printf '%s' "$ver" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || die "version must be X.Y.Z with no leading 'v' (got '$ver')"

root="$(git rev-parse --show-toplevel)" || die "not in a git repo"
cd "$root"
cl="CHANGELOG.md"
[ -f "$cl" ] || die "$cl not found"
today="$(date +%F)"

# Promote [Unreleased] -> [X.Y.Z] and rewrite the link refs. Reads the previous tag from the
# existing [Unreleased] compare link (matches the file rather than trusting `git tag`).
promote() { # promote <in> <out>
  awk -v ver="$ver" -v today="$today" '
    !done_head && /^## \[Unreleased\]$/ {
      print; print ""; print "## [" ver "] - " today; done_head = 1; next
    }
    /^\[Unreleased\]:[[:space:]]/ && index($0, "/compare/") > 0 {
      ci = index($0, "/compare/"); prefix = substr($0, 1, ci - 1)
      sub(/^\[Unreleased\]:[[:space:]]*/, "", prefix)
      rest = substr($0, ci + 9); di = index(rest, "..."); oldbase = substr(rest, 1, di - 1)
      print "[Unreleased]: " prefix "/compare/v" ver "...HEAD"
      print "[" ver "]: " prefix "/compare/" oldbase "...v" ver
      next
    }
    { print }
  ' "$1" >"$2"
}

if [ "$dry" -eq 1 ]; then
  tmp="$(mktemp)"
  promote "$cl" "$tmp"
  diff -u "$cl" "$tmp" | sed "s#$tmp#CHANGELOG.md (promoted to v$ver)#" || true
  rm -f "$tmp"
  exit 0
fi

# --- preconditions (real run) ----------------------------------------------------------------
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "must be on 'main' (you are on $(git rev-parse --abbrev-ref HEAD))"
[ -z "$(git status --porcelain)" ] || die "working tree not clean -- commit or stash first"
git rev-parse -q --verify "refs/tags/v$ver" >/dev/null && die "tag v$ver already exists"
have="$(awk '/^## \[Unreleased\]/{f=1;next} /^## \[/{f=0} f' "$cl" | grep -Ec '^(###|- |> )' || true)"
[ "${have:-0}" -gt 0 ] || die "[Unreleased] has no entries -- nothing to release"
if git fetch -q origin main 2>/dev/null; then
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
    || die "local main is behind/ahead of origin/main -- sync first"
fi

# --- do it -----------------------------------------------------------------------------------
promote "$cl" "$cl.tmp"
mv "$cl.tmp" "$cl"
git --no-pager diff -- "$cl"
git add "$cl"
git commit -m "chore(release): v$ver"
git tag "v$ver"

cat <<EOF

✓ Released v$ver locally (commit + tag). Nothing pushed yet.
  review : git show v$ver
  publish: git push origin main v$ver      # pre-push guard verifies CHANGELOG matches the tag
  undo   : git tag -d v$ver && git reset --hard HEAD~1
EOF
