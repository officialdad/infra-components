output "alb_arn" {
  value       = aws_lb.this.arn
  description = "ARN of the load balancer."
}

output "alb_dns_name" {
  value       = aws_lb.this.dns_name
  description = "DNS name of the load balancer."
}

output "target_group_arn" {
  value       = aws_lb_target_group.this.arn
  description = "ARN of the default target group."
}

output "security_group_id" {
  value       = aws_security_group.this.id
  description = "Security group ID of the load balancer."
}
