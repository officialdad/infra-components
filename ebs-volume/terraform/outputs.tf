output "volumes" {
  description = "Created EBS volumes keyed by their volumes-map key. `name` is the Name tag the consuming instance discovers and self-attaches by. `backup_tag` is the Backup tag value snapshots are listed by and `snapshot_policy` the DLM policy id; both are null when the entry has no `snapshot`."
  value = {
    for k, v in aws_ebs_volume.this : k => {
      volume_id         = v.id
      arn               = v.arn
      availability_zone = v.availability_zone
      name              = "${var.global.environment_name}-${k}"
      backup_tag        = try(v.tags["Backup"], null)
      snapshot_policy   = try(aws_dlm_lifecycle_policy.this[k].id, null)
    }
  }
}
