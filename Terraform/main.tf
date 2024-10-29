# Configure AWS Provider
provider "aws" {
  region = var.aws_region
}

# Data source to get the default VPC
data "aws_vpc" "default" {
  default = true
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
}

resource "aws_eip" "nat_eip_az2" {
  domain = "vpc"

  tags = {
    Name = "nat-eip-az2"
  }
}

# NAT Gateways
resource "aws_nat_gateway" "nat_gateway_az1" {
  allocation_id = aws_eip.nat_eip_az1.id
  subnet_id     = aws_subnet.public_subnet_az1.id

  tags = {
    Name = "nat-gateway-az1"
  }
}

resource "aws_nat_gateway" "nat_gateway_az2" {
  allocation_id = aws_eip.nat_eip_az2.id
  subnet_id     = aws_subnet.public_subnet_az2.id

  tags = {
    Name = "nat-gateway-az2"
  }
}

# Private Route Tables
resource "aws_route_table" "private_rt_az1" {
  vpc_id = aws_vpc.ecommerce_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway_az1.id
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

# VPC Peering Routes in Custom VPC
resource "aws_route" "custom_vpc_public_rt_to_default_vpc" {
  route_table_id            = aws_route_table.public_rt.id
  destination_cidr_block    = data.aws_vpc.default.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.default_to_custom.id
}

resource "aws_route" "custom_vpc_private_rt_az1_to_default_vpc" {
  route_table_id            = aws_route_table.private_rt_az1.id
  destination_cidr_block    = data.aws_vpc.default.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.default_to_custom.id
}

resource "aws_route" "custom_vpc_private_rt_az2_to_default_vpc" {
  route_table_id            = aws_route_table.private_rt_az2.id
  destination_cidr_block    = data.aws_vpc.default.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.default_to_custom.id
}

# VPC Peering Route in Default VPC
resource "aws_route" "default_vpc_route_to_custom_vpc" {
  route_table_id            = data.aws_route_table.default_main.id
  destination_cidr_block    = aws_vpc.ecommerce_vpc.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.default_to_custom.id
}

# Security Groups
resource "aws_security_group" "frontend_security_group" {
  name        = "frontend-sg"
  description = "Security group for frontend EC2 instances"
  vpc_id      = aws_vpc.ecommerce_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "React"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Django"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

# Load Balancer
resource "aws_lb" "frontend_lb" {
  name               = "frontend-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.frontend_security_group.id]
  subnets            = [aws_subnet.public_subnet_az1.id, aws_subnet.public_subnet_az2.id]

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
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
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

# Frontend EC2 Instances
resource "aws_instance" "ecommerce_frontend_az1" {
  ami           = "ami-0c7217cdde317cfec" # Ubuntu 22.04 LTS in us-east-1
  instance_type = var.instance_type
  key_name      = var.key_name

  subnet_id                   = aws_subnet.public_subnet_az1.id
  vpc_security_group_ids      = [aws_security_group.frontend_security_group.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/../scripts/frontend_user_data.sh", {
    backend_private_ip    = aws_instance.ecommerce_backend_az1.private_ip
    NODE_EXPORTER_VERSION = var.NODE_EXPORTER_VERSION # Added variable
  })


  tags = {
    Name = "ecommerce_frontend_az1"
  }

  depends_on = [aws_instance.ecommerce_backend_az1]
}

resource "aws_instance" "ecommerce_frontend_az2" {
  ami           = "ami-0c7217cdde317cfec" # Ubuntu 22.04 LTS in us-east-1
  instance_type = var.instance_type
  key_name      = var.key_name

  subnet_id                   = aws_subnet.public_subnet_az2.id
  vpc_security_group_ids      = [aws_security_group.frontend_security_group.id]
  associate_public_ip_address = true

  user_data = templatefile("${path.module}/../scripts/frontend_user_data.sh", {
    backend_private_ip    = aws_instance.ecommerce_backend_az2.private_ip
    NODE_EXPORTER_VERSION = var.NODE_EXPORTER_VERSION # Added variable
  })


  tags = {
    Name = "ecommerce_frontend_az2"
  }

  depends_on = [aws_instance.ecommerce_backend_az2]
}

# Backend EC2 Instances
resource "aws_instance" "ecommerce_backend_az1" {
  ami           = "ami-0c7217cdde317cfec" # Ubuntu 22.04 LTS in us-east-1
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
  })


  tags = {
    Name = "ecommerce_backend_az1"
  }

  depends_on = [aws_db_instance.postgres_db]
}

resource "aws_instance" "ecommerce_backend_az2" {
  ami           = "ami-0c7217cdde317cfec" # Ubuntu 22.04 LTS in us-east-1
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
  })


  tags = {
    Name = "ecommerce_backend_az2"
  }

  depends_on = [aws_db_instance.postgres_db]
}

# Target Group Attachments
resource "aws_lb_target_group_attachment" "frontend_tg_attachment_1" {
  target_group_arn = aws_lb_target_group.frontend_tg.arn
  target_id        = aws_instance.ecommerce_frontend_az1.id
  port             = 3000
}

resource "aws_lb_target_group_attachment" "frontend_tg_attachment_2" {
  target_group_arn = aws_lb_target_group.frontend_tg.arn
  target_id        = aws_instance.ecommerce_frontend_az2.id
  port             = 3000
}

# RDS Database
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

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds_subnet_group"
  subnet_ids = [aws_subnet.private_subnet_az1.id, aws_subnet.private_subnet_az2.id]

  tags = {
    Name = "RDS subnet group"
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "rds_sg"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.ecommerce_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_security_group.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDS Security Group"
  }
}
