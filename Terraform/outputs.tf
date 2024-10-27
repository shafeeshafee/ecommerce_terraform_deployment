# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.ecommerce_vpc.id
}

# Load Balancer Outputs
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.frontend_lb.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the Application Load Balancer"
  value       = aws_lb.frontend_lb.zone_id
}

# EC2 Instance Outputs
output "frontend_instance_az1_ip" {
  description = "Public IP of frontend instance in AZ1"
  value       = aws_instance.ecommerce_frontend_az1.public_ip
}

output "frontend_instance_az2_ip" {
  description = "Public IP of frontend instance in AZ2"
  value       = aws_instance.ecommerce_frontend_az2.public_ip
}

output "backend_instance_az1_private_ip" {
  description = "Private IP of backend instance in AZ1"
  value       = aws_instance.ecommerce_backend_az1.private_ip
}

output "backend_instance_az2_private_ip" {
  description = "Private IP of backend instance in AZ2"
  value       = aws_instance.ecommerce_backend_az2.private_ip
}

# RDS Outputs
output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.postgres_db.endpoint
}

output "rds_database_name" {
  description = "Name of the RDS database"
  value       = aws_db_instance.postgres_db.db_name
}

output "rds_port" {
  description = "Port of the RDS instance"
  value       = "5432"
}

# Subnet Outputs
output "public_subnet_az1_id" {
  description = "ID of public subnet in AZ1"
  value       = aws_subnet.public_subnet_az1.id
}

output "public_subnet_az2_id" {
  description = "ID of public subnet in AZ2"
  value       = aws_subnet.public_subnet_az2.id
}

output "private_subnet_az1_id" {
  description = "ID of private subnet in AZ1"
  value       = aws_subnet.private_subnet_az1.id
}

output "private_subnet_az2_id" {
  description = "ID of private subnet in AZ2"
  value       = aws_subnet.private_subnet_az2.id
}

# Security Group Outputs
output "frontend_sg_id" {
  description = "ID of the frontend security group"
  value       = aws_security_group.frontend_security_group.id
}

output "backend_sg_id" {
  description = "ID of the backend security group"
  value       = aws_security_group.backend_security_group.id
}

output "rds_sg_id" {
  description = "ID of the RDS security group"
  value       = aws_security_group.rds_sg.id
}
