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
    root_disk_size_gb = optional(number, 20)
    assign_public_ip  = optional(bool, false)
    user_data         = optional(string, "")
  }))
  description = "EC2 instances to create, keyed by short name. Each entry overrides only the fields it needs; the rest take module defaults. Instance Name tag = \"<env>-<key>\". Empty ami = latest Amazon Linux 2023."
  default     = {}

  validation {
    condition     = alltrue([for k in keys(var.instances) : can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$|^[a-z]$", k))])
    error_message = "Each instances key must be: lowercase letter first, then lowercase/digits/hyphens, no trailing hyphen, ≤63 chars."
  }
}
