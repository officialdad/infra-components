terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Plain aws_ebs_volume resource — no wrapped module forcing a higher floor
      # (unlike ec2). Bounded ~> 6.0 like the other AWS foundation components.
      version = "~> 6.0"
    }
  }
}
