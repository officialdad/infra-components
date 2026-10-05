terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Plain aws_cloudwatch_metric_alarm / aws_sns_topic resources - no wrapped module forcing a
      # higher floor (unlike ec2). Bounded ~> 6.0 like the other AWS components.
      version = "~> 6.0"
    }
  }
}
