provider "aws" {
  region = var.global.deploy_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "${var.global.environment_name}-vpc"
  azs         = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Carve one /20 private + one /20 public subnet per AZ out of the VPC CIDR.
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.cidr_block, 4, i)]
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.cidr_block, 4, i + var.az_count)]

  common_tags = merge(var.global.tags, {
    ManagedBy   = "terraform"
    Environment = var.global.environment_name
  })
}

# VPC + public/private subnets + NAT via the verified community module,
# mirroring how the GCP network wraps the CFT module.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = local.name_prefix
  cidr = var.cidr_block

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  # Single NAT gateway gives no-public-IP instances egress (incl. reaching SSM).
  enable_nat_gateway = var.enable_nat_gateway
  single_nat_gateway = var.enable_nat_gateway

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = local.common_tags
}
