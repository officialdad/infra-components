#!/usr/bin/env bash
# SessionStart: ensure local git hooks are installed, then print environment truth + the
# working contract. stdout is added to the model's context, grounding the session in real state.
set -uo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

# Install this repo's git hooks (pre-commit + commit-msg via the framework; native pre-push tag
# guard) so the agent's own commits/tags go through them — combined with the --no-verify denial in
# tf-guard, they can't be skipped. Idempotent and fast (environments build lazily on first commit).
if [ -f "$root/scripts/setup-hooks.sh" ]; then
  ( cd "$root" && bash scripts/setup-hooks.sh >/dev/null 2>&1 ) &&
    hooks="git hooks: installed (pre-commit + commit-msg + pre-push)" ||
    hooks="git hooks: partial install — run scripts/setup-hooks.sh (pre-commit installed?)"
else
  hooks="git hooks: scripts/setup-hooks.sh missing — commits/tags unchecked locally"
fi

if command -v terraform >/dev/null 2>&1; then
  tf="$(terraform version | head -1)"
else
  tf="terraform: NOT INSTALLED"
fi
if command -v tflint >/dev/null 2>&1; then
  tl="tflint: $(tflint --version 2>/dev/null | head -1)"
else
  tl="tflint: NOT INSTALLED (gate skips lint — install: https://github.com/terraform-linters/tflint)"
fi
br="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

cat <<EOF
infra-components — reusable Terraform module library. Validate-only here; apply lives in the environments repos.
toolchain: ${tf} | ${tl} | branch: ${br}
${hooks}
Quality gate is ON (.claude/settings.json): *.tf edits auto-format; before a turn ends, fmt/validate/tflint run on changed components and BLOCK on failure. apply/destroy and git --no-verify are denied; commits follow Conventional Commits.
Ground Terraform facts via the \`terraform\` MCP server (mcp__terraform__*), not memory or context7. Conventions: CLAUDE.md.
EOF
exit 0
