output "role_arn" {
  value       = aws_iam_role.ci.arn
  description = "ARN of the CI role. Consumed by the env unit → repo secret AWS_ROLE_ARN (used by aws-actions/configure-aws-credentials)."
}

output "oidc_provider_arn" {
  value       = local.oidc_arn
  description = "ARN of the GitHub OIDC provider (created here, or the existing one passed in)."
}

output "role_name" {
  value       = aws_iam_role.ci.name
  description = "Name of the CI role."
}
