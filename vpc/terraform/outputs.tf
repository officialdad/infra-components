output "vpc_id" {
  value       = aws_vpc.this.id
  description = "The ID of the VPC."
}

output "cidr_block" {
  value       = aws_vpc.this.cidr_block
  description = "The CIDR block of the VPC."
}

# Map of tier name -> list of subnet IDs. Downstream components index into this
# (e.g. subnet_ids_list_by_name.private) the same way the reference setup does.
output "subnet_ids_list_by_name" {
  value = {
    public  = aws_subnet.public[*].id
    private = aws_subnet.private[*].id
  }
  description = "Subnet IDs grouped by tier name (public/private)."
}
