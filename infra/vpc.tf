# vpc.tf
# Defines the Network Infrastructure: VPC, Subnets, IGW, Route Tables, and Security Groups

# 1. VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

# 2. Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

# 3. Subnets (Public)
# We utilize Public Subnets for both Control Plane and Workers to avoid NAT Gateway costs ($0.045/hr).
# In a non-Free-Tier production environment, Workers should be in Private Subnets with a NAT Gateway.

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.cluster_name}-public-subnet-a"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned" # Required for AWS Load Balancer Controller discovery (if used)
    "kubernetes.io/role/elb"                    = "1"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "${var.cluster_name}-public-subnet-b"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    "kubernetes.io/role/elb"                    = "1"
  }
}

# 4. Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# 5. Security Groups

# Security Group for the Load Balancer
resource "aws_security_group" "alb_sg" {
  name        = "${var.cluster_name}-alb-sg"
  description = "Allow inbound HTTP traffic from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound to anywhere"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-alb-sg"
  }
}

# Security Group for K3s Nodes (Control Plane & Workers)
resource "aws_security_group" "k3s_node_sg" {
  name        = "${var.cluster_name}-node-sg"
  description = "Security group for K3s nodes"
  vpc_id      = aws_vpc.main.id

  # Allow internal communication (Flannel/VXLAN, Kubelet, Etcd, etc.)
  ingress {
    description = "Self Reference - All Traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow Traffic from ALB
  ingress {
    description     = "HTTP from ALB"
    from_port       = 30000 # NodePort range start
    to_port         = 32767 # NodePort range end
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # SSH Access (Restrict to User IP in prod, open to world for demo/simplicity or use Session Manager)
  # Using 0.0.0.0/0 for demo ease, but flagging as security risk. Use Session Manager ideally.
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }
  
  # Kubernetes API (6443) - Open to world for 'kubectl' from local machine
  ingress {
    description = "K8s API Server"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  egress {
    description = "Outbound to anywhere"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-node-sg"
  }
}
