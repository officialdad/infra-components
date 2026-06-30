---
name: release
description: Cut a versioned release of this module library — generate the CHANGELOG section from Conventional Commits with git-cliff, tag vX.Y.Z, and push. Use when the user asks to release, cut a tag, bump the version, or publish a new version.
---

# Cut a release

Automates steps 3–4 of README's **Versioning & releasing** flow. The mechanics live in
`scripts/release.sh`: it **generates** the new CHANGELOG section from the unreleased Conventional
Commits with **git-cliff** (`cliff.toml`), splices it under `## [Unreleased]`, fixes the compare
links, commits, and tags — **no push, no hand-curation**. Your job is the judgment around it: pick
the version, confirm it has soaked, and confirm the irreversible push.

> **Single source of truth.** The changelog is generated from commit subjects, not curated. The same
> git-cliff config backs the GitHub Release, so `CHANGELOG.md` == the GitHub Release by construction.
> History ≤ `v0.6.0` is frozen (it predates the commit gate); only the new section is generated. The
> way to improve an entry is to improve its **commit subject** — there is no `[Unreleased]` block to
> edit.

## 1. Preconditions — check before doing anything
- **git-cliff is installed** (`git-cliff --version`). `scripts/release.sh` needs it to generate the
  section and aborts with an install hint if it's missing (see README "Toolchain").
- On `main`, clean tree, in sync with `origin/main`. (`scripts/release.sh` re-checks and aborts if not.)
- The change has **soaked in `infra-environments-dev`**. If you can't confirm it has, **ASK the
  user** — never tag something that hasn't actually run in dev.
- There are **consumer-facing commits since the last tag** (`feat`/`fix`/`refactor`/`perf`/`revert`/
  breaking). A range of only `chore`/`ci`/`docs` generates an empty section and `release.sh` refuses
  ("nothing to release") — that's correct, not an error to work around.

## 2. Pick the version (X.Y.Z)
If the user didn't give one, propose it from the last tag (`git tag --sort=-v:refname | head -1`) and
the nature of the unreleased commits (preview them: `scripts/release.sh X.Y.Z --dry-run`), per
README's rules:
- **MAJOR** — breaking input/output change (callers must edit their config).
- **MINOR** — new component/feature, backward compatible.
- **PATCH** — bug fix, no interface change.

Watch the `required_version` floor: raising it can break consumers pinned below it (MAJOR territory).
State your proposed bump and **get the user's confirmation** before proceeding.

## 3. Cut it locally (reversible)
1. Preview: `scripts/release.sh X.Y.Z --dry-run` — shows the **generated section** + the CHANGELOG
   diff. If an entry reads poorly, the fix is the commit subject (amend before tagging), not the file.
2. Cut: `scripts/release.sh X.Y.Z` — generates `## [X.Y.Z] - <today>` from the commits, splices it,
   fixes the compare links, commits `chore(release): vX.Y.Z`, and tags `vX.Y.Z`. **Nothing is pushed.**
3. Show `git show vX.Y.Z --stat`. This is the last reversible point:
   `git tag -d vX.Y.Z && git reset --hard HEAD~1`.

## 4. Publish — only after explicit user confirmation (irreversible)
`git push origin main vX.Y.Z`
- The **`pre-push` guard** refuses the push unless `CHANGELOG.md` has the matching `## [X.Y.Z] - <date>`
  section (it will pass — you just generated it).
- The pushed tag triggers `.github/workflows/changelog.yml`'s `release` job, which publishes the
  **GitHub Release** from the same git-cliff config — so the GitHub Release matches the CHANGELOG
  section. Don't hand-write release notes.

## 5. After — remind the user of the last manual step
Promote to prod: a PR in `infra-environments-prod` bumping the component's pin (`vOLD` → `vX.Y.Z`),
reviewed, then applied. Prod only ever moves to a tag.

> Never auto-release on merge — tagging stays a deliberate human call. This skill is the convenience,
> not a bypass of that judgment.
