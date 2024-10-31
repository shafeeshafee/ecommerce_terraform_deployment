# Configure AWS Provider
provider "aws" {
  region = var.aws_region
}

# Data source to get the default VPC
data "aws_vpc" "default" {
  default = true
}

# Data source for getting latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Get the main route table for the default VPC
data "aws_route_table" "default_main" {
  vpc_id = data.aws_vpc.default.id
  filter {
    name   = "association.main"
    values = ["true"]
  }
}

# VPC
resource "aws_vpc" "ecommerce_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "wl5vpc"
  }
}

# VPC Peering Connection
resource "aws_vpc_peering_connection" "default_to_custom" {
  vpc_id      = data.aws_vpc.default.id
  peer_vpc_id = aws_vpc.ecommerce_vpc.id
  auto_accept = true

  tags = {
    Name = "default-to-custom-peering"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.ecommerce_vpc.id

  tags = {
    Name = "ecommerce-igw"
  }
}

# Public Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.ecommerce_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  route {
    cidr_block                = data.aws_vpc.default.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.default_to_custom.id
  }

  tags = {
    Name = "public-rt"
  }
}

# Public Subnets
resource "aws_subnet" "public_subnet_az1" {
  vpc_id                  = aws_vpc.ecommerce_vpc.id
  cidr_block              = var.public_subnet_az1_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-az1"
  }
}

resource "aws_subnet" "public_subnet_az2" {
  vpc_id                  = aws_vpc.ecommerce_vpc.id
  cidr_block              = var.public_subnet_az2_cidr
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-az2"
  }
}

# Route Table Associations for public subnets
resource "aws_route_table_association" "public_rt_assoc_az1" {
  subnet_id      = aws_subnet.public_subnet_az1.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_rt_assoc_az2" {
  subnet_id      = aws_subnet.public_subnet_az2.id
  route_table_id = aws_route_table.public_rt.id
}

# Private Subnets
resource "aws_subnet" "private_subnet_az1" {
  vpc_id            = aws_vpc.ecommerce_vpc.id
  cidr_block        = var.private_subnet_az1_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "private-subnet-az1"
  }
}

resource "aws_subnet" "private_subnet_az2" {
  vpc_id            = aws_vpc.ecommerce_vpc.id
  cidr_block        = var.private_subnet_az2_cidr
  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "private-subnet-az2"
  }
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat_eip_az1" {
  domain = "vpc"

  tags = {
    Name = "nat-eip-az1"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_eip" "nat_eip_az2" {
  domain = "vpc"

  tags = {
    Name = "nat-eip-az2"
  }

  depends_on = [aws_internet_gateway.igw]
}

# NAT Gateways
resource "aws_nat_gateway" "nat_gateway_az1" {
  allocation_id = aws_eip.nat_eip_az1.id
  subnet_id     = aws_subnet.public_subnet_az1.id

  tags = {
    Name = "nat-gateway-az1"
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat_gateway_az2" {
  allocation_id = aws_eip.nat_eip_az2.id
  subnet_id     = aws_subnet.public_subnet_az2.id

  tags = {
    Name = "nat-gateway-az2"
  }

  depends_on = [aws_internet_gateway.igw]
}

# Private Route Tables
resource "aws_route_table" "private_rt_az1" {
  vpc_id = aws_vpc.ecommerce_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway_az1.id
  }

  route {
    cidr_block                = data.aws_vpc.default.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.default_to_custom.id
  }

  tags = {
    Name = "private-rt-az1"
  }
}

resource "aws_route_table" "private_rt_az2" {
  vpc_id = aws_vpc.ecommerce_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway_az2.id
  }

  route {
    cidr_block                = data.aws_vpc.default.cidr_block
    vpc_peering_connection_id = aws_vpc_peering_connection.default_to_custom.id
  }

  tags = {
    Name = "private-rt-az2"
  }
}

# Route Table Associations for private subnets
resource "aws_route_table_association" "private_rt_assoc_az1" {
  subnet_id      = aws_subnet.private_subnet_az1.id
  route_table_id = aws_route_table.private_rt_az1.id
}

resource "aws_route_table_association" "private_rt_assoc_az2" {
  subnet_id      = aws_subnet.private_subnet_az2.id
  route_table_id = aws_route_table.private_rt_az2.id
}

# VPC Peering Route in Default VPC
resource "aws_route" "default_vpc_route_to_custom_vpc" {
  route_table_id            = data.aws_route_table.default_main.id
  destination_cidr_block    = aws_vpc.ecommerce_vpc.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.default_to_custom.id
}

# Security Groups
resource "aws_security_group" "alb_security_group" {
  name        = "alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.ecommerce_vpc.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
  }
}

resource "aws_security_group" "frontend_security_group" {
  name        = "frontend-sg"
  description = "Security group for frontend EC2 instances"
  vpc_id      = aws_vpc.ecommerce_vpc.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "Allow traffic from ALB on port 3000"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_security_group.id]
  }

  ingress {
    description = "Node Exporter"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "frontend-sg"
  }
}

resource "aws_security_group" "backend_security_group" {
  name        = "backend-sg"
  description = "Security group for backend EC2 instances"
  vpc_id      = aws_vpc.ecommerce_vpc.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "Allow Django traffic from frontend"
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend_security_group.id]
  }

  ingress {
    description = "Node Exporter"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "backend-sg"
  }
}

# RDS Security Group - Define before RDS instance
resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.ecommerce_vpc.id

  ingress {
    description     = "PostgreSQL from backend"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_security_group.id]
  }

  ingress {
    description = "PostgreSQL from Default VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg"
  }
}

# RDS Subnet Group
resource "aws_db_subnet_group" "rds_subnet_group" {
  name_prefix = "rds-subnet-group-"
  subnet_ids  = [aws_subnet.private_subnet_az1.id, aws_subnet.private_subnet_az2.id]

  tags = {
    Name = "RDS subnet group"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# RDS Instance
resource "aws_db_instance" "postgres_db" {
  identifier           = "ecommerce-db"
  engine               = "postgres"
  engine_version       = "14.13"
  instance_class       = var.db_instance_class
  allocated_storage    = 20
  storage_type         = "standard"
  db_name              = var.db_name
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = "default.postgres14"
  skip_final_snapshot  = true

  db_subnet_group_name   = aws_db_subnet_group.rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  tags = {
    Name = "Ecommerce Postgres DB"
  }
}

# Load Balancer
resource "aws_lb" "frontend_lb" {
  name               = "frontend-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_security_group.id]
  subnets            = [aws_subnet.public_subnet_az1.id, aws_subnet.public_subnet_az2.id]

  enable_deletion_protection = false

  tags = {
    Name = "frontend-lb"
  }
}

resource "aws_lb_target_group" "frontend_tg" {
  name     = "frontend-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = aws_vpc.ecommerce_vpc.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "3000"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = {
    Name = "frontend-tg"
  }
}

resource "aws_lb_listener" "frontend_listener" {
  load_balancer_arn = aws_lb.frontend_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_tg.arn
  }
}

# Backend EC2 Instances - Create these first
resource "aws_instance" "ecommerce_backend_az1" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  subnet_id              = aws_subnet.private_subnet_az1.id
  vpc_security_group_ids = [aws_security_group.backend_security_group.id]

  user_data = templatefile("${path.module}/../scripts/backend_user_data.sh", {
    db_name               = var.db_name
    db_username           = var.db_username
    db_password           = var.db_password
    rds_endpoint          = aws_db_instance.postgres_db.address
    NODE_EXPORTER_VERSION = var.NODE_EXPORTER_VERSION
    instance_name         = "ecommerce_backend_az1"
    allowed_hosts         = aws_lb.frontend_lb.dns_name
  })

  tags = {
    Name = "ecommerce_backend_az1"
  }

  depends_on = [aws_db_instance.postgres_db]
}

resource "aws_instance" "ecommerce_backend_az2" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  subnet_id              = aws_subnet.private_subnet_az2.id
  vpc_security_group_ids = [aws_security_group.backend_security_group.id]

  user_data = templatefile("${path.module}/../scripts/backend_user_data.sh", {
    db_name               = var.db_name
    db_username           = var.db_username
    db_password           = var.db_password
    rds_endpoint          = aws_db_instance.postgres_db.address
    NODE_EXPORTER_VERSION = var.NODE_EXPORTER_VERSION
    instance_name         = "ecommerce_backend_az2"
    allowed_hosts         = aws_lb.frontend_lb.dns_name
  })

  tags = {
    Name = "ecommerce_backend_az2"
  }

  depends_on = [aws_db_instance.postgres_db]
}

# Frontend EC2 Instances - Create these after backends
resource "aws_instance" "ecommerce_frontend_az1" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  subnet_id                   = aws_subnet.public_subnet_az1.id
  vpc_security_group_ids      = [aws_security_group.frontend_security_group.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/../scripts/frontend_user_data.sh", {
    backend_private_ip    = aws_instance.ecommerce_backend_az1.private_ip
    NODE_EXPORTER_VERSION = var.NODE_EXPORTER_VERSION
  })

  tags = {
    Name = "ecommerce_frontend_az1"
  }

  depends_on = [aws_instance.ecommerce_backend_az1]
}

resource "aws_instance" "ecommerce_frontend_az2" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  subnet_id                   = aws_subnet.public_subnet_az2.id
  vpc_security_group_ids      = [aws_security_group.frontend_security_group.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/../scripts/frontend_user_data.sh", {
    backend_private_ip    = aws_instance.ecommerce_backend_az2.private_ip
    NODE_EXPORTER_VERSION = var.NODE_EXPORTER_VERSION
  })

  tags = {
    Name = "ecommerce_frontend_az2"
  }

  depends_on = [aws_instance.ecommerce_backend_az2]
}

# Target Group Attachments
resource "aws_lb_target_group_attachment" "frontend_tg_attachment_1" {
  target_group_arn = aws_lb_target_group.frontend_tg.arn
  target_id        = aws_instance.ecommerce_frontend_az1.id
  port             = 3000

  depends_on = [aws_instance.ecommerce_frontend_az1]
}

resource "aws_lb_target_group_attachment" "frontend_tg_attachment_2" {
  target_group_arn = aws_lb_target_group.frontend_tg.arn
  target_id        = aws_instance.ecommerce_frontend_az2.id
  port             = 3000

  depends_on = [aws_instance.ecommerce_frontend_az2]
}
