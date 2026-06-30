#!/usr/bin/env bash
# Canary for issue #21: assert the antonbabenko pre-commit Terraform hooks actually match the .tf
# files changed in a PR, instead of silently reporting "(no files to check)" — which once let a brand
# new component's Terraform slip past the local fmt/validate/tflint gate (false confidence).
#
# Probes terraform_fmt only: it shares the identical `files: \.(tf|tofu|tfvars)$` predicate with
# terraform_validate/terraform_tflint, so if fmt matches the changed set they all do — and fmt needs
# no init/providers/tflint, keeping the CI canary cheap. Run by CI on PRs; runnable locally too:
#   scripts/check-precommit-tf-coverage.sh <from-ref> <to-ref>   # e.g. origin/main HEAD
set -uo pipefail

from_ref="${1:?usage: $0 <from-ref> <to-ref>}"
to_ref="${2:?usage: $0 <from-ref> <to-ref>}"

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "check-precommit-tf-coverage: not in a git repo" >&2; exit 1; }
cd "$root"

# Terraform files changed in the range (added/copied/modified/renamed — the cases a commit stages).
mapfile -t changed_tf < <(git diff --name-only --diff-filter=ACMR "$from_ref" "$to_ref" -- '*.tf' '*.tofu' '*.tfvars')

if [ "${#changed_tf[@]}" -eq 0 ]; then
  echo "check-precommit-tf-coverage: no Terraform files changed in ${from_ref}..${to_ref} — nothing to assert."
  exit 0
fi

echo "check-precommit-tf-coverage: ${#changed_tf[@]} changed Terraform file(s); asserting the hooks match them:"
printf '  %s\n' "${changed_tf[@]}"

# --from-ref/--to-ref makes pre-commit resolve the same changed-file set a commit would, then run the
# hook against it. A correct run prints Passed/Failed; a silent skip prints "(no files to check)".
out="$(pre-commit run terraform_fmt --from-ref "$from_ref" --to-ref "$to_ref" 2>&1)"
echo "$out"

if grep -q 'no files to check' <<<"$out"; then
  echo "::error::pre-commit hook 'terraform_fmt' reported '(no files to check)' despite changed Terraform —" \
       "the Terraform hooks silently skipped the change (issue #21). The local fmt/validate/tflint gate is not" \
       "covering these files. Check the antonbabenko/pre-commit-terraform pin and staged-file resolution." >&2
  exit 1
fi

# Belt and braces: a Passed/Failed result line proves pre-commit actually ran the hook. Its absence
# means pre-commit bailed before running it (e.g. unstaged config, missing tool) — don't green-wash that.
if ! grep -q 'Terraform fmt' <<<"$out"; then
  echo "::error::pre-commit did not run 'terraform_fmt' (no result line) — see output above; cannot confirm" \
       "the Terraform hooks covered the changed files." >&2
  exit 1
fi

echo "check-precommit-tf-coverage: OK — the Terraform hooks matched the changed files (no silent skip)."
