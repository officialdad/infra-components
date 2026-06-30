#!/usr/bin/env bash
# Cut a release: GENERATE the new CHANGELOG section from Conventional Commits with git-cliff, splice
# it under `## [Unreleased]` as `## [X.Y.Z] - <today>`, fix the two compare links, then commit
# `chore(release): vX.Y.Z` and tag `vX.Y.Z` -- LOCALLY. Nothing is pushed.
# Review with `git show vX.Y.Z`; publish with `git push origin main vX.Y.Z` (a pre-push guard
# checks the tag matches the CHANGELOG). Undo before pushing:
#   git tag -d vX.Y.Z && git reset --hard HEAD~1
#
# The release notes are GENERATED, not curated: git-cliff (config: cliff.toml) is the single source
# of truth and the same generator backs the GitHub Release, so CHANGELOG.md == the Release notes.
# History at v0.6.0 and older is frozen (it predates the commit gate) -- only the new section is
# generated and spliced; the existing sections are never rewritten.
#
# Requires: git-cliff on PATH (https://github.com/orhun/git-cliff -- see README "Toolchain").
#
# Usage: scripts/release.sh X.Y.Z [--dry-run]
#   --dry-run  print the generated section + CHANGELOG diff only; touch nothing, skip git-state checks.
set -euo pipefail

die() { printf 'release: %s\n' "$1" >&2; exit 1; }

ver="${1:-}"
dry=0
[ "${2:-}" = "--dry-run" ] && dry=1
[ -n "$ver" ] || die "usage: scripts/release.sh X.Y.Z [--dry-run]"
printf '%s' "$ver" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || die "version must be X.Y.Z with no leading 'v' (got '$ver')"

command -v git-cliff >/dev/null 2>&1 \
  || die "git-cliff not found on PATH -- install it (see README 'Toolchain'); release notes are generated from commits"

root="$(git rev-parse --show-toplevel)" || die "not in a git repo"
cd "$root"
cl="CHANGELOG.md"
[ -f "$cl" ] || die "$cl not found"

# Generate the new version's section from the unreleased Conventional Commits. git-cliff dates the
# unreleased-as-vX.Y.Z block with TODAY (verified: not the last-commit date), so no date surgery is
# needed. `--strip header` keeps only the section body. Trailing blank lines are trimmed so the
# splice leaves exactly one blank line before the previous version.
section_file="$(mktemp)"
gen_err="$(mktemp)"
if ! git-cliff --config cliff.toml --unreleased --tag "v$ver" --strip header >"$section_file.raw" 2>"$gen_err"; then
  cat "$gen_err" >&2; rm -f "$section_file" "$section_file.raw" "$gen_err"; die "git-cliff failed to generate the changelog section"
fi
awk '{ a[NR] = $0 } END { last = NR; while (last > 0 && a[last] == "") last--; for (i = 1; i <= last; i++) print a[i] }' \
  "$section_file.raw" >"$section_file"
rm -f "$section_file.raw" "$gen_err"

# A release whose only commits are chore/ci/docs/etc. produces a heading with no entries -- there is
# nothing consumer-facing to release.
grep -Eq '^(### |- )' "$section_file" \
  || { rm -f "$section_file"; die "no consumer-facing changes since the last tag (only skipped commit types) -- nothing to release"; }

# Splice the generated section under `## [Unreleased]` and rewrite the two compare links. The
# previous tag is read from the existing [Unreleased] compare link (trust the file, not `git tag`).
splice() { # splice <changelog-in> <section-file> <out>
  awk -v ver="$ver" -v secfile="$2" '
    !spliced && /^## \[Unreleased\]$/ {
      print; print ""
      while ((getline line < secfile) > 0) print line
      close(secfile)
      spliced = 1; next
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
  ' "$1" >"$3"
}

if [ "$dry" -eq 1 ]; then
  printf '=== generated section (v%s) ===\n' "$ver"
  cat "$section_file"
  printf '\n=== CHANGELOG.md diff ===\n'
  tmp="$(mktemp)"
  splice "$cl" "$section_file" "$tmp"
  diff -u "$cl" "$tmp" | sed "s#$tmp#CHANGELOG.md (released v$ver)#" || true
  rm -f "$tmp" "$section_file"
  exit 0
fi

# --- preconditions (real run) ----------------------------------------------------------------
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || die "must be on 'main' (you are on $(git rev-parse --abbrev-ref HEAD))"
[ -z "$(git status --porcelain)" ] || die "working tree not clean -- commit or stash first"
git rev-parse -q --verify "refs/tags/v$ver" >/dev/null && die "tag v$ver already exists"
if git fetch -q origin main 2>/dev/null; then
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
    || die "local main is behind/ahead of origin/main -- sync first"
fi

# --- do it -----------------------------------------------------------------------------------
splice "$cl" "$section_file" "$cl.tmp"
mv "$cl.tmp" "$cl"
rm -f "$section_file"
git --no-pager diff -- "$cl"
git add "$cl"
git commit -m "chore(release): v$ver"
# Annotated (-m), not lightweight: when tag.gpgsign/forceSignAnnotated is set, git makes the tag
# signed+annotated and a non-interactive run with no message aborts ("fatal: no tag message?"),
# leaving the release commit tagless. A message satisfies that and auto-signs when configured.
git tag -m "Release v$ver" "v$ver"

cat <<EOF

✓ Released v$ver locally (commit + tag). Nothing pushed yet.
  review : git show v$ver
  publish: git push origin main v$ver      # pre-push guard verifies CHANGELOG matches the tag
  undo   : git tag -d v$ver && git reset --hard HEAD~1
EOF
