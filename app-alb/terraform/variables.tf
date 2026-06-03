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
  description = "VPC the load balancer and target group live in."
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs to attach the load balancer to."
}

variable "target_port" {
  type        = number
  description = "Port the target group forwards to."
  default     = 8080
}

variable "health_check_path" {
  type        = string
  description = "HTTP path used for target group health checks."
  default     = "/health"
}

variable "internal" {
  type        = bool
  description = "Whether the load balancer is internal (true) or internet-facing (false)."
  default     = false
}
