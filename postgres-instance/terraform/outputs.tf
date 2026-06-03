output "database_address" {
  value       = aws_db_instance.this.address
  description = "The hostname of the RDS instance."
}

output "database_endpoint" {
  value       = aws_db_instance.this.endpoint
  description = "The connection endpoint (host:port)."
}

output "database_arn" {
  value       = aws_db_instance.this.arn
  description = "The ARN of the RDS instance."
}

output "security_group_id" {
  value       = aws_security_group.this.id
  description = "The security group ID protecting the database."
}

output "database_username" {
  value       = aws_db_instance.this.username
  description = "Master username."
}

output "database_password" {
  value       = random_password.master.result
  description = "Generated master password."
  sensitive   = true
}
