provider "aws" {
  region = var.global.deploy_region
}

locals {
  common_tags = merge(var.global.tags, {
    ManagedBy   = "terraform"
    Environment = var.global.environment_name
  })
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

  tags = merge(local.common_tags, {
    Name = "${var.global.environment_name}-${each.key}"
  })
}
