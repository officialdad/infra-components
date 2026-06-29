output "policy_arns" {
  value       = { for k, p in aws_iam_policy.this : k => p.arn }
  description = "Managed policy ARNs keyed by their policies-map key. Feed an entry into a consumer role, e.g. ec2 iam_role_policy_arns."
}
