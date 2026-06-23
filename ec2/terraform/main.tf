provider "aws" {
  region = var.global.deploy_region
}

locals {
  common_tags = merge(var.global.tags, {
    ManagedBy   = "terraform"
    Environment = var.global.environment_name
  })
}

# VPC CIDR, so named ingress rules are reachable from inside the network only.
data "aws_vpc" "this" {
  id = var.vpc_id
}

# Per-instance SG via the verified module: named ingress rules (e.g.
# "prometheus-http-tcp" -> 9090) from the VPC CIDR; egress open so SSM reaches
# the instance via NAT. Empty ingress_rules = egress-only (SSM-only, no inbound).
module "sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  for_each = var.instances

  name        = "${var.global.environment_name}-${each.key}"
  description = "Egress-all; named ingress from the VPC CIDR. Empty = SSM-only, no inbound."
  vpc_id      = var.vpc_id

  ingress_rules       = each.value.ingress_rules
  ingress_cidr_blocks = [data.aws_vpc.this.cidr_block]
  egress_rules        = ["all-all"]

  tags = local.common_tags
}

# One or more EC2 instances via the verified module. No public IP by default;
# access is SSM Session Manager (the module builds the IAM role + instance
# profile from create_iam_instance_profile + the SSM managed policy).
# AMI selection per instance: literal ami wins; else ami_ssm_parameter tracks the
# latest image (defaults to Amazon Linux 2023). Lets an env pick its OS (e.g. Ubuntu)
# without hardcoding a region-locked AMI id.
# Bootstrap-agnostic: runs each instance's user_data, "" = none.
module "ec2" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 6.0"

  for_each = var.instances

  name = "${var.global.environment_name}-${each.key}"

  instance_type               = each.value.instance_type
  ami                         = each.value.ami != "" ? each.value.ami : null
  ami_ssm_parameter           = each.value.ami_ssm_parameter != "" ? each.value.ami_ssm_parameter : "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  subnet_id                   = var.subnet_id
  associate_public_ip_address = each.value.assign_public_ip
  user_data                   = each.value.user_data != "" ? each.value.user_data : null

  create_security_group  = false
  vpc_security_group_ids = [module.sg[each.key].security_group_id]

  create_iam_instance_profile = true
  iam_role_policies = {
    ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  root_block_device = {
    size = each.value.root_disk_size_gb
  }

  tags = local.common_tags
}
