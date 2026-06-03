variable "global" {
  type = object({
    environment_name = string
    deploy_region    = string
    tags             = map(string)
  })
  description = "Environment-wide context injected by the environments repo (name, region, tags)."
}

variable "pet_length" {
  type        = number
  description = "Number of words in the generated pet name."
  default     = 2
}

variable "message" {
  type        = string
  description = "A message written into the generated artifact file."
  default     = "hello from the dummy component"
}
