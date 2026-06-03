variable "global" {
  type = object({
    environment_name = string
    deploy_region    = string
    tags             = map(string)
  })
  description = "Environment-wide context injected by the environments repo (name, region, tags)."
}

variable "database_identifier" {
  type        = string
  description = "The identifier of the database instance."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnet IDs for the DB subnet group (typically the VPC's private subnets)."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID the database security group is created in."
}

variable "database_instance_class" {
  type        = string
  description = "The RDS instance class."
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  type        = number
  description = "Allocated storage in GB."
  default     = 20
}

variable "engine_version" {
  type        = string
  description = "PostgreSQL engine version."
  default     = "16.3"
}

variable "database_name" {
  type        = string
  description = "Name of the initial database to create."
  default     = "appdb"
}

variable "database_username" {
  type        = string
  description = "Master username."
  default     = "appadmin"
}

variable "multi_az" {
  type        = bool
  description = "Enable Multi-AZ deployment."
  default     = false
}
