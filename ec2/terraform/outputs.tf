output "instances" {
  description = "Created EC2 instances keyed by their instances-map key."
  value = {
    for k, vm in aws_instance.this : k => {
      name        = vm.tags["Name"]
      instance_id = vm.id
      private_ip  = vm.private_ip
      ssm_command = "aws ssm start-session --target ${vm.id} --region ${var.global.deploy_region}"
    }
  }
}
