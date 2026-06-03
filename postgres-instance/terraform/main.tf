provider "aws" {
  region = var.global.deploy_region
}

locals {
  name_prefix = "${var.global.environment_name}-${var.database_identifier}"

  common_tags = merge(var.global.tags, {
    ManagedBy   = "terraform"
    Environment = var.global.environment_name
  })
}

# Generate a master password rather than accepting one as plaintext input.
# In a real setup this would typically be stored in Secrets Manager / Vault.
resource "random_password" "master" {
  length  = 24
  special = false
}

resource "aws_db_subnet_group" "this" {
  name       = "${local.name_prefix}-subnets"
  subnet_ids = var.subnet_ids

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-subnets" })
}

resource "aws_security_group" "this" {
  name        = "${local.name_prefix}-sg"
  description = "Security group for the ${local.name_prefix} PostgreSQL instance."
  vpc_id      = var.vpc_id

  egress {
    description = "Allow all outbound."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-sg" })
}

resource "aws_db_instance" "this" {
  identifier     = local.name_prefix
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.database_instance_class

  allocated_storage = var.allocated_storage
  storage_encrypted = true

  db_name  = var.database_name
  username = var.database_username
  password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.this.id]
  multi_az               = var.multi_az

  skip_final_snapshot = true
  apply_immediately   = true

  tags = merge(local.common_tags, { Name = local.name_prefix })
}
