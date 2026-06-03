# A credential-free component used to exercise the full CI/CD pipeline (plan -> PR
# comment -> gated apply) without any cloud account. It creates real Terraform
# resources, just local ones: a random name, a local file, and a null trigger.

locals {
  name_prefix = "${var.global.environment_name}-dummy"
}

resource "random_pet" "name" {
  length = var.pet_length
  prefix = local.name_prefix
}

resource "local_file" "artifact" {
  filename = "${path.module}/generated/${local.name_prefix}.txt"
  content  = <<-EOT
    environment : ${var.global.environment_name}
    region      : ${var.global.deploy_region}
    pet         : ${random_pet.name.id}
    message     : ${var.message}
  EOT
}

# A null_resource whose trigger changes when the pet name changes — gives the plan
# a visible "must replace" example when inputs change.
resource "null_resource" "marker" {
  triggers = {
    pet = random_pet.name.id
  }
}
