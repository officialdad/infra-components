provider "aws" {
  region = var.global.deploy_region
}

locals {
  common_tags = merge(var.global.tags, {
    ManagedBy   = "terraform"
    Environment = var.global.environment_name
  })

  # DLM selects volumes by the dedicated Backup tag, never Name: Name is what the instance
  # attaches by and can drift, and a drifted Name would silently stop snapshots with no error.
  snapshot_volumes = { for k, v in var.volumes : k => v.snapshot if v.snapshot != null }
}

# One standalone EBS volume per entry, in its own state — decoupled from any EC2
# instance lifecycle so the data survives a compute destroy/apply. Naming is
# deterministic (no suffix); the Name tag is how the instance self-attaches.
# encrypted is hardcoded true (matching the ec2 root volume, not the account default).
# Attachment is NOT modeled here: the consuming env's user_data finds the volume by
# Name tag and attaches/mounts it, scoped by an iam-policy grant on the instance role.
resource "aws_ebs_volume" "this" {
  for_each = var.volumes

  availability_zone = each.value.availability_zone
  size              = each.value.size_gb
  type              = each.value.type
  iops              = each.value.iops
  throughput        = each.value.throughput
  encrypted         = true
  final_snapshot    = each.value.final_snapshot

  tags = merge(
    local.common_tags,
    { Name = "${var.global.environment_name}-${each.key}" },
    each.value.snapshot != null ? { Backup = "${var.global.environment_name}-${each.key}" } : {},
  )
}

# One role shared by every volume that opts into snapshots. The name starts with the environment
# name and a dash so the CI role's IAM scope (automation-roles) already covers it.
resource "aws_iam_role" "dlm" {
  count = length(local.snapshot_volumes) > 0 ? 1 : 0

  name = "${var.global.environment_name}-ebs-volume-dlm"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "dlm.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "dlm" {
  count = length(local.snapshot_volumes) > 0 ? 1 : 0

  role       = aws_iam_role.dlm[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

# One policy per volume, not one for all: DLM rejects two policies that share target_tags, and
# schedule and retention are per-volume settings. copy_tags puts the Backup tag on each snapshot so
# snapshots can be listed by it. Snapshots are crash-consistent (no pre/post scripts).
resource "aws_dlm_lifecycle_policy" "this" {
  for_each = local.snapshot_volumes

  description        = "Daily snapshots of ${var.global.environment_name}-${each.key}"
  execution_role_arn = aws_iam_role.dlm[0].arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags    = { Backup = "${var.global.environment_name}-${each.key}" }

    schedule {
      name      = "${var.global.environment_name}-${each.key}-daily"
      copy_tags = true

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = each.value.times
      }

      retain_rule {
        count = each.value.retain_count
      }
    }
  }

  tags = local.common_tags

  # The role must have its permissions before DLM validates the policy against it.
  depends_on = [aws_iam_role_policy_attachment.dlm]
}
