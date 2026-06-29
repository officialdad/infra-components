provider "aws" {
  region = var.global.deploy_region
}

data "aws_caller_identity" "current" {}

locals {
  common_tags = merge(var.global.tags, {
    ManagedBy   = "terraform"
    Environment = var.global.environment_name
  })

  role_name = var.role_name != "" ? var.role_name : "${var.global.environment_name}-github-actions-ci"

  # Recommended default: scope by repo + ref/event (apply on main, plan on PRs) rather than a
  # bare repo:org/repo:* wildcard. Override allowed_subjects to change.
  subjects = length(var.allowed_subjects) > 0 ? var.allowed_subjects : [
    "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/main",
    "repo:${var.github_org}/${var.github_repo}:pull_request",
  ]

  oidc_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : var.existing_oidc_provider_arn

  # IAM resources the ec2 component's instance profile lives under, scoped to this account + the
  # env name prefix so the CI role can only touch its own roles/profiles.
  account_id = data.aws_caller_identity.current.account_id
  iam_scope = [
    "arn:aws:iam::${local.account_id}:role/${var.global.environment_name}-*",
    "arn:aws:iam::${local.account_id}:instance-profile/${var.global.environment_name}-*",
  ]
}

# Account-global singleton federating GitHub Actions OIDC tokens. thumbprint_list is intentionally
# omitted: optional in the AWS provider (>= 5.x / 6.x) — AWS validates this provider against its own
# CA trust store, so a hardcoded thumbprint would only rot.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

  tags = local.common_tags
}

# Trust: only GitHub-issued tokens for the allowed repo/ref subjects, audience sts.amazonaws.com.
data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.subjects
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = local.role_name
  description        = "GitHub Actions CI role for ${var.github_org}/${var.github_repo} (plan/apply vpc + ec2)."
  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = local.common_tags
}

# Least-privilege first pass for what the vpc + ec2 components create. Issue #7: start scoped,
# tighten iteratively from plan errors. Most EC2/VPC create+describe actions don't support
# resource-level scoping, hence Resource = "*"; IAM and SSM are scoped.
data "aws_iam_policy_document" "permissions" {
  # VPC + EC2. EC2 actions almost all require Resource = "*" (no resource-level scoping), so
  # enumerating verbs is churn without real isolation — the privilege-escalation surface is IAM,
  # which stays scoped below. Bound instead by region: the role can only act on EC2 in this env's
  # deploy_region.
  statement {
    sid       = "VpcAndEc2"
    effect    = "Allow"
    actions   = ["ec2:*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [var.global.deploy_region]
    }
  }

  # IAM: the ec2 module's create_iam_instance_profile builds an instance role + profile and attaches
  # AmazonSSMManagedInstanceCore. Scoped to <env>-* roles/profiles in this account; PassRole too.
  statement {
    sid    = "InstanceProfileIam"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:PassRole",
    ]
    resources = local.iam_scope
  }

  # SSM read: the ec2 module resolves ami_ssm_parameter (public AL2023 / Ubuntu image params).
  statement {
    sid    = "SsmImageParams"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = ["arn:aws:ssm:*::parameter/aws/service/*"]
  }
}

# Standalone managed policy (auditable, reusable) rather than an inline role policy.
resource "aws_iam_policy" "ci" {
  name        = "${local.role_name}-policy"
  description = "Least-privilege policy for CI to plan/apply the vpc + ec2 components."
  policy      = data.aws_iam_policy_document.permissions.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ci" {
  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.ci.arn
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = toset(var.additional_policy_arns)

  role       = aws_iam_role.ci.name
  policy_arn = each.value
}
