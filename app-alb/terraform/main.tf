provider "aws" {
  region = var.global.deploy_region
}

locals {
  name_prefix = "${var.global.environment_name}-alb"

  common_tags = merge(var.global.tags, {
    ManagedBy   = "terraform"
    Environment = var.global.environment_name
  })
}

resource "aws_security_group" "this" {
  name        = "${local.name_prefix}-sg"
  description = "Security group for the ${local.name_prefix} load balancer."
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTP from anywhere."
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-sg" })
}

resource "aws_lb" "this" {
  name               = local.name_prefix
  internal           = var.internal
  load_balancer_type = "application"
  security_groups    = [aws_security_group.this.id]
  subnets            = var.public_subnet_ids

  tags = merge(local.common_tags, { Name = local.name_prefix })
}

resource "aws_lb_target_group" "this" {
  name        = "${local.name_prefix}-tg"
  port        = var.target_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = var.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-tg" })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
