#!/usr/bin/env bash
# SessionStart: print environment truth + the working contract. stdout is added to the
# model's context, grounding the session in real state instead of assumptions.
set -uo pipefail

root="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
tf="$(terraform version 2>/dev/null | head -1 || echo 'terraform: NOT INSTALLED')"
if command -v tflint >/dev/null 2>&1; then
  tl="tflint: $(tflint --version 2>/dev/null | head -1)"
else
  tl="tflint: NOT INSTALLED (gate skips lint — install: https://github.com/terraform-linters/tflint)"
fi
br="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

cat <<EOF
infra-components — reusable Terraform module library. Validate-only here; apply lives in the environments repos.
toolchain: ${tf} | ${tl} | branch: ${br}
Quality gate is ON (.claude/settings.json): *.tf edits auto-format; before a turn ends, fmt/validate/tflint run on changed components and BLOCK on failure. apply/destroy and git --no-verify are denied.
Ground Terraform facts via the \`terraform\` MCP server (mcp__terraform__*), not memory or context7. Conventions: CLAUDE.md.
EOF
exit 0
