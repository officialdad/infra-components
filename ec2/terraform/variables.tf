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

variable "subnet_id" {
  type        = string
  description = "Subnet all instances launch into (from vpc.private_subnet_ids[0]). Use a private subnet for no-public-IP, SSM-only access."
}

variable "instances" {
  type = map(object({
    instance_type     = optional(string, "t3.micro")
    ami               = optional(string, "")
    ami_ssm_parameter = optional(string, "")
    root_disk_size_gb = optional(number, 20)
    assign_public_ip  = optional(bool, false)
    user_data         = optional(string, "")
    ingress_rules     = optional(list(string), [])
  }))
  description = "EC2 instances to create, keyed by short name. Each entry overrides only the fields it needs; the rest take module defaults. Instance Name tag = \"<env>-<key>\". OS selection: set ami to a literal AMI id (wins if set), OR set ami_ssm_parameter to a public SSM parameter to track the latest image (e.g. Ubuntu: \"/aws/service/canonical/ubuntu/server/26.04/stable/current/amd64/hvm/ebs-gp3/ami-id\"); both empty = latest Amazon Linux 2023. ingress_rules are named rules from terraform-aws-modules/security-group (e.g. [\"prometheus-http-tcp\"]); empty = SSM-only, no inbound. Each instance gets its own SG, reachable from the VPC CIDR only."
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.instances) : can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$|^[a-z]$", k))])
    error_message = "Each instances key must be: lowercase letter first, then lowercase/digits/hyphens, no trailing hyphen, ≤63 chars."
  }
}
