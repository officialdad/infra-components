provider "aws" {
  region = var.global.deploy_region
}

locals {
  common_tags = merge(var.global.tags, {
    ManagedBy   = "terraform"
    Environment = var.global.environment_name
  })
}

# One managed policy per entry. The body is the caller's document verbatim — this component models
# no IAM semantics, it only names/tags it and exposes the ARN. Name is deterministic (no suffix).
resource "aws_iam_policy" "this" {
  for_each = var.policies

  name        = "${var.global.environment_name}-${each.key}"
  description = each.value.description != "" ? each.value.description : "Managed by terraform (iam-policy) for ${var.global.environment_name}."
  policy      = each.value.policy_json

  tags = local.common_tags
}
