output "volumes" {
  description = "Created EBS volumes keyed by their volumes-map key. `name` is the Name tag the consuming instance discovers and self-attaches by."
  value = {
    for k, v in aws_ebs_volume.this : k => {
      volume_id         = v.id
      arn               = v.arn
      availability_zone = v.availability_zone
      name              = "${var.global.environment_name}-${k}"
    }
  }
}
