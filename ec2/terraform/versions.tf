terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Higher floor than the other AWS components' ~> 6.0: the wrapped
      # terraform-aws-modules/ec2-instance (v6) requires aws >= 6.37. Bounded to 6.x
      # so a major provider bump is a deliberate change, matching the ~> style elsewhere.
      version = "~> 6.37"
    }
  }
}
