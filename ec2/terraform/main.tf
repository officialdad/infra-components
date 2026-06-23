provider "aws" {
  region = var.global.deploy_region
}

# Latest Amazon Linux 2023 AMI via the public SSM parameter (per-region resolved).
# UNVERIFIED until plan — confirm with: aws ssm get-parameters --names <this> --region <region>
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  common_tags = merge(var.global.tags, {
    ManagedBy   = "terraform"
    Environment = var.global.environment_name
  })
}

# Egress-only SG: SSM reaches the instance outbound (via NAT); no inbound SSH.
resource "aws_security_group" "this" {
  name_prefix = "${var.global.environment_name}-ec2-"
  description = "Egress-only; access via SSM Session Manager (no inbound SSH)."
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# Instance profile granting SSM Session Manager — the IAP/OS-Login analog.
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name_prefix        = "${var.global.environment_name}-ec2-ssm-"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "this" {
  name_prefix = "${var.global.environment_name}-ec2-"
  role        = aws_iam_role.this.name
}

resource "aws_instance" "this" {
  for_each = var.instances

  ami                         = each.value.ami != "" ? each.value.ami : data.aws_ssm_parameter.al2023.value
  instance_type               = each.value.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.this.id]
  iam_instance_profile        = aws_iam_instance_profile.this.name
  associate_public_ip_address = each.value.assign_public_ip
  user_data                   = each.value.user_data != "" ? each.value.user_data : null

  root_block_device {
    volume_size = each.value.root_disk_size_gb
  }

  tags = merge(local.common_tags, { Name = "${var.global.environment_name}-${each.key}" })
}
