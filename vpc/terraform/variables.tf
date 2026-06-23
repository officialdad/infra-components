variable "global" {
  type = object({
    environment_name = string
    deploy_region    = string
    tags             = map(string)
  })
  description = "Environment-wide context injected by the environments repo (name, region, tags)."
}

variable "cidr_block" {
  type        = string
  description = "Primary IPv4 CIDR of the VPC."
  default     = "10.0.0.0/16"
}

variable "az_count" {
  type        = number
  description = "Number of AZs to spread private/public subnets across."
  default     = 2
}

variable "enable_nat_gateway" {
  type        = bool
  description = "Create a single NAT gateway so private (no-public-IP) instances get egress, including reaching AWS Systems Manager (SSM)."
  default     = true
}
