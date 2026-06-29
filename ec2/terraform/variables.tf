variable "global" {
  type = object({
    environment_name = string
    deploy_region    = string
    tags             = map(string)
  })
  description = "Environment-wide context injected by the environments repo (name, region, tags)."
}

variable "vpc_id" {
  type        = string
  description = "VPC the instances and their security group live in (from vpc.vpc_id)."
}

variable "vpc_cidr" {
  type        = string
  description = "VPC CIDR for SG ingress rules (from vpc.vpc_cidr_block). Replaces a live aws_vpc lookup so ec2 plans greenfield."
}

variable "subnet_id" {
  type        = string
  description = "Subnet all instances launch into (from vpc.private_subnet_ids[0]). Use a private subnet for no-public-IP, SSM-only access."
}

variable "instances" {
  type = map(object({
    instance_type        = optional(string, "t3.micro")
    ami                  = optional(string, "")
    ami_ssm_parameter    = optional(string, "")
    root_disk_size_gb    = optional(number, 20)
    assign_public_ip     = optional(bool, false)
    user_data            = optional(string, "")
    ingress_rules        = optional(list(string), [])
    iam_role_policy_arns = optional(map(string), {})
  }))
  description = "EC2 instances keyed by short name; each entry overrides only what it needs. Name tag = \"<env>-<key>\". OS: literal ami wins, else ami_ssm_parameter tracks latest image (default Amazon Linux 2023). ingress_rules = named SG rules (empty = SSM-only, no inbound). iam_role_policy_arns = extra policy ARNs (static keys) on the instance role, atop the always-on SSM core policy."
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.instances) : can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$|^[a-z]$", k))])
    error_message = "Each instances key must be: lowercase letter first, then lowercase/digits/hyphens, no trailing hyphen, ≤63 chars."
  }
}
