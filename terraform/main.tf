provider "aws" {
  region = "ap-south-1" # Change the region as needed
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "main-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet"
  }
}

# Private Subnet
resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.2.0/24"

  tags = {
    Name = "private-subnet"
  }
}

# Route Table for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "public-rt"
  }
}

# Associate Public Subnet with Route Table
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group for SSH access
resource "aws_security_group" "ssh" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

   # Allow traffic on port 5000 only from the NLB
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"] 
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ssh-sg"
  }
}

# Generate a Key Pair
resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = "generated-key"
  public_key = tls_private_key.example.public_key_openssh
}

resource "local_file" "private_key" {
  content  = tls_private_key.example.private_key_pem
  filename = "${path.module}/generated-key.pem"
}

# EC2 Instance in Public Subnet
resource "aws_instance" "web" {
  ami             = "ami-0c76ded57b818ac02" # Ubuntu 20
  instance_type   = "t2.micro"
  subnet_id       = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ssh.id]
  associate_public_ip_address = true
  key_name        = aws_key_pair.generated_key.key_name

  tags = {
    Name = "web-server"
  }

 # Ensure the instance creation waits for the security group to be created
  depends_on = [aws_security_group.ssh]
}

# Network Load Balancer (NLB)
resource "aws_lb" "nlb" {
  name               = "web-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.public.id]

  tags = {
    Name = "web-nlb"
  }
}

# Create a target group
resource "aws_lb_target_group" "tg" {
  name     = "web-tg"
  port     = 5000
  protocol = "TCP"
  vpc_id   = aws_vpc.main.id
}

# Add the EC2 instance to the target group
resource "aws_lb_target_group_attachment" "tg_attachment" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.web.id
  port             = 5000
}

# Create a listener for the NLB
resource "aws_lb_listener" "nlb_listener" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 5000
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "flask_api" {
  name        = "Flask API"
  description = "API Gateway for Flask app"
}

resource "aws_api_gateway_resource" "flask_api_resource" {
  rest_api_id = aws_api_gateway_rest_api.flask_api.id
  parent_id   = aws_api_gateway_rest_api.flask_api.root_resource_id
  path_part   = "flask"
}

# VPC Link
resource "aws_api_gateway_vpc_link" "vpc_link" {
  name        = "vpc-link"
  target_arns = [aws_lb.nlb.arn]
}

resource "aws_api_gateway_method" "flask_api_method" {
  rest_api_id   = aws_api_gateway_rest_api.flask_api.id
  resource_id   = aws_api_gateway_resource.flask_api_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "flask_api_integration" {
  rest_api_id             = aws_api_gateway_rest_api.flask_api.id
  resource_id             = aws_api_gateway_resource.flask_api_resource.id
  http_method             = aws_api_gateway_method.flask_api_method.http_method
  type                    = "HTTP_PROXY"
  integration_http_method = "GET"
  uri                     = "http://${aws_lb.nlb.dns_name}:5000/flask"
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.vpc_link.id
}

resource "aws_api_gateway_deployment" "flask_api_deploy" {
  depends_on = [aws_api_gateway_integration.flask_api_integration]
  rest_api_id = aws_api_gateway_rest_api.flask_api.id
  stage_name  = "prod"
}

output "public_instance_ip" {
  value = aws_instance.web.public_ip
}

output "private_instance_ip" {
  value = aws_instance.web.private_ip
}

output "private_key_path" {
  value = local_file.private_key.filename
}

output "api_gateway_endpoint" {
  value = aws_api_gateway_deployment.flask_api_deploy.invoke_url
}
