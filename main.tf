terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
provider "aws" {
  region = "us-west-1"

}
resource "aws_vpc" "vpc_testing" {
    cidr_block = "10.0.0.0/24"
    enable_dns_hostnames = true
    enable_dns_support = true
    tags = {
      Name="vpc_testing"
    }
}
resource "aws_subnet" "pub_subnet1" {
    vpc_id = aws_vpc.vpc_testing.id
    cidr_block = "10.0.0.0/26"
    availability_zone = "us-west-1a"
    map_public_ip_on_launch = true
    tags = {
      Name="pub_subnet1"
    }
}
resource "aws_subnet" "pub_subnet2" {
    vpc_id = aws_vpc.vpc_testing.id
    cidr_block = "10.0.0.64/26"
    availability_zone = "us-west-1c"
    map_public_ip_on_launch = true
    tags = {
      Name="pub_subnet2"
    }
}
resource "aws_subnet" "private_subnet1" {
    vpc_id = aws_vpc.vpc_testing.id
    cidr_block = "10.0.0.128/26"
    availability_zone = "us-west-1c"
    tags = {
      Name="private_subnet"
    }
}
resource "aws_subnet" "private_subnet2" {
    vpc_id = aws_vpc.vpc_testing.id
    cidr_block = "10.0.0.192/26"
    availability_zone = "us-west-1a"
    tags = {
      Name="private_subnet2"
    }
}
resource "aws_internet_gateway" "testing_gateway" {
    vpc_id = aws_vpc.vpc_testing.id
    tags = {
      Name="testing_gateway"
    }
}
resource "aws_route_table" "testing_route_table" {
    vpc_id = aws_vpc.vpc_testing.id
    route {
      cidr_block = "0.0.0.0/0"
      gateway_id = aws_internet_gateway.testing_gateway.id
    }
}
resource "aws_route_table_association" "testing_route_table_association" {
    route_table_id = aws_route_table.testing_route_table.id
    subnet_id = aws_subnet.pub_subnet1.id
}
resource "aws_route_table_association" "testing_route_table_association2" {
    route_table_id = aws_route_table.testing_route_table.id
    subnet_id = aws_subnet.pub_subnet2.id
}
resource "aws_security_group" "load-balancer-sg" {
    name = "load-balancer-sg"
    description = "Security group for load balancer"
    vpc_id = aws_vpc.vpc_testing.id
    ingress {
      from_port = 80
      to_port = 80
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
    egress  {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
}
resource "aws_security_group" "ec2_sg" {
    name = "ec2-sg"
    vpc_id = aws_vpc.vpc_testing.id
    ingress {
      from_port = 80
      to_port = 80
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
      security_groups = [aws_security_group.load-balancer-sg.id]
    }
    #for the ssh access
    ingress {
      from_port = 22
      to_port = 22
      protocol = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
    egress  {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
}
resource "aws_security_group" "database_sg" {
    name = "database_sg"
    vpc_id = aws_vpc.vpc_testing.id
    ingress {
      from_port = 3306
      to_port = 3306
      protocol = "tcp"
      security_groups = [aws_security_group.ec2_sg.id]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
}
resource "aws_lb" "project_lb" {
  name               = "project-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.load-balancer-sg.id]
  subnets            = [aws_subnet.pub_subnet1.id,aws_subnet.pub_subnet2.id]
  tags = {
    Name = "project_lb"
  }
}
resource "aws_lb_target_group" "project_target_group" {
  name     = "project-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.vpc_testing.id
}
resource "aws_lb_listener" "project_listener" {
  load_balancer_arn = aws_lb.project_lb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.project_target_group.arn
  }
}
resource "aws_instance" "testing_project" {
  ami = "ami-00271c85bf8a52b84"
  instance_type = "t2.micro"
  key_name = "terraform_project"
  subnet_id = aws_subnet.pub_subnet1.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true
  user_data = <<-EOF
              #!/bin/bash
              sudo apt-get update
              sudo apt-get install -y apache2
              sudo systemctl start apache2
              sudo systemctl enable apache2 
              EOF
  tags = {
    Name = "testing_project"
  }
}
resource "aws_ami_from_instance" "load_balancers_servers" {
  name = "load_balancers_server"
  source_instance_id = aws_instance.testing_project.id
  lifecycle {
    create_before_destroy = true
  } 
}
resource "aws_launch_template" "project_launch_template" {
  name_prefix = "project-launch-template"
  image_id = aws_ami_from_instance.load_balancers_servers.id
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
}
resource "aws_autoscaling_group" "project_auto_scaling_group" {
  desired_capacity    = 2
  max_size            = 3
  min_size            = 2
  vpc_zone_identifier = [aws_subnet.pub_subnet1.id, aws_subnet.pub_subnet2.id]
  launch_template {
    id = aws_launch_template.project_launch_template.id
    version = "$Latest"
  }  
  target_group_arns = [aws_lb_target_group.project_target_group.arn]
  health_check_type = "EC2"
}
resource "aws_db_subnet_group" "database_group" {
  subnet_ids = [aws_subnet.private_subnet1.id,aws_subnet.private_subnet2.id]
  name= "database_group"
}
resource "aws_db_instance" "database" {
  identifier = "chandu"
  allocated_storage    = 10
  db_name              = "mysqldatabase"
  engine               = "mysql"
  instance_class       = "db.t3.micro"
  username             = "admin"
  password             = "admin12345"
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.database_group.name
  vpc_security_group_ids = [aws_security_group.database_sg.id]
  multi_az = true
}
