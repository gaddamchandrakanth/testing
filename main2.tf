terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
provider "aws" {
  region = "us-east-1"
}
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/24"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "main_vpc"
  }
}
resource "aws_subnet" "subnet1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.0/25"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "subnet1"
  }
}
resource "aws_subnet" "subnet2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.0.128/25"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "subnet2"
  }
}
resource "aws_internet_gateway" "internet" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main_igw"
  }
}
resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet.id
  }
}
resource "aws_route_table_association" "subnet1_route" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.route_table.id
}
resource "aws_route_table_association" "subnet2_route" {
  subnet_id = aws_subnet.subnet2.id
  route_table_id = aws_route_table.route_table.id
}
resource "aws_iam_role" "cluster_role" {
  name = "cluster_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "policy_attachment" {
  role = aws_iam_role.cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}
resource "aws_iam_role_policy_attachment" "vpc_policy_attachment" {
  role = aws_iam_role.cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}
resource "aws_eks_cluster" "main" {
  name = "main"
  role_arn = aws_iam_role.cluster_role.arn
  vpc_config {
    subnet_ids = [ aws_subnet.subnet1.id,aws_subnet.subnet2.id ]
    endpoint_private_access = false
    endpoint_public_access = true
  }
  depends_on = [ aws_iam_role_policy_attachment.policy_attachment,aws_iam_role_policy_attachment.vpc_policy_attachment ] 
}
resource "aws_iam_role" "node_cluster_role" {
  name = "node_cluster_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "node_policy_attachment" {
  role = aws_iam_role.node_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}
resource "aws_iam_role_policy_attachment" "vpc_node_policy_attachment" {
  role = aws_iam_role.node_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}
resource "aws_eks_node_group" "node_cluster" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "node_cluster"
  node_role_arn   = aws_iam_role.node_cluster_role.arn
  subnet_ids      = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
  scaling_config {
    desired_size = 2
    max_size     = 2
    min_size     = 2
  }
  depends_on = [ aws_iam_role_policy_attachment.node_policy_attachment,aws_iam_role_policy_attachment.vpc_node_policy_attachment ]
  instance_types = ["t2.micro"]
}



