---
name: release
description: Cut a versioned release of this module library — promote CHANGELOG [Unreleased] to a dated section, tag vX.Y.Z, and push. Use when the user asks to release, cut a tag, bump the version, or publish a new version.
---

# Cut a release

Automates steps 3–4 of README's **Versioning & releasing** flow. The mechanics live in
`scripts/release.sh` (deterministic text surgery + commit + tag, no push). Your job is the judgment
around it: pick the version, confirm it has soaked, and confirm the irreversible push.

## 1. Preconditions — check before doing anything
- On `main`, clean tree, in sync with `origin/main`. (`scripts/release.sh` re-checks and aborts if not.)
- The change has **soaked in `infra-environments-dev`** (which tracks `main`). If you can't confirm
  it has, **ASK the user** — never tag something that hasn't actually run in dev.
- `## [Unreleased]` in `CHANGELOG.md` has entries (that's what gets published).

## 2. Pick the version (X.Y.Z)
If the user didn't give one, propose it from the last tag (`git tag --sort=-v:refname | head -1`) and
the nature of `[Unreleased]`, per README's rules:
- **MAJOR** — breaking input/output change (callers must edit their config).
- **MINOR** — new component/feature, backward compatible.
- **PATCH** — bug fix, no interface change.

Watch the `required_version` floor: raising it can break consumers pinned below it (MAJOR territory).
State your proposed bump and **get the user's confirmation** before proceeding.

## 3. Cut it locally (reversible)
1. Preview: `scripts/release.sh X.Y.Z --dry-run` — show the user the CHANGELOG diff.
2. Cut: `scripts/release.sh X.Y.Z` — promotes `[Unreleased]` → `## [X.Y.Z] - <today>`, fixes the
   compare links, commits `chore(release): vX.Y.Z`, and tags `vX.Y.Z`. **Nothing is pushed.**
3. Show `git show vX.Y.Z --stat`. This is the last reversible point:
   `git tag -d vX.Y.Z && git reset --hard HEAD~1`.

## 4. Publish — only after explicit user confirmation (irreversible)
`git push origin main vX.Y.Z`
- The **`pre-push` guard** refuses the push unless the CHANGELOG was promoted to match (it will pass
  — you just promoted it).
- The pushed tag triggers `.github/workflows/changelog.yml`'s `release` job, which publishes the
  **GitHub Release** notes from the tagged commits. Don't hand-write release notes.

## 5. After — remind the user of the last manual step
Promote to prod: a PR in `infra-environments-prod` bumping the component's pin (`vOLD` → `vX.Y.Z`),
reviewed, then applied. Prod only ever moves to a tag.

> Never auto-release on merge — tagging stays a deliberate human call. This skill is the convenience,
> not a bypass of that judgment.
