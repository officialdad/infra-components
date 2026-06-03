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
  description = "The CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "az_count" {
  type        = number
  description = "Number of availability zones to spread subnets across."
  default     = 3

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 3
    error_message = "az_count must be between 1 and 3."
  }
}

variable "public_subnet_newbits" {
  type        = number
  description = "Additional bits to extend the VPC prefix by for each public subnet (cidrsubnet)."
  default     = 8
}

variable "private_subnet_newbits" {
  type        = number
  description = "Additional bits to extend the VPC prefix by for each private subnet (cidrsubnet)."
  default     = 8
}
