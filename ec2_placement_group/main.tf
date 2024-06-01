locals {
  private = {
    jumphost  = "10.0.1.5/32"
    webserver = "10.0.2.6/32"
  }
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "ec2-placement-group-${random_string.suffix.result}"
  }
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.example.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "private"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "public"
  }
}

resource "aws_ec2_subnet_cidr_reservation" "jumphost" {
  cidr_block       = local.private.jumphost
  reservation_type = "prefix"
  subnet_id        = aws_subnet.private.id
}

resource "aws_ec2_subnet_cidr_reservation" "webserver" {
  cidr_block       = local.private.webserver
  reservation_type = "prefix"
  subnet_id        = aws_subnet.public.id
}

resource "aws_security_group" "jumphost" {
  name   = "ec2-placement-group-${random_string.suffix.result}"
  vpc_id = aws_vpc.example.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "webserver" {
  vpc_id = aws_vpc.example.id

  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_subnet.public.cidr_block]
  }

  ingress {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [
        "0.0.0.0/0"
      ]
    }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "example" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  depends_on = [
    aws_internet_gateway.example
  ]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.example.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.example.id
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_ec2_instance_connect_endpoint" "example" {
  subnet_id = aws_subnet.public.id

  tags = {
    Name = "ec2-placement-group-${random_string.suffix.result}"
  }
}

data "aws_ami" "amzn2023" {
  most_recent = true

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "name"
    values = ["al2023-ami-2023*"]
  }
}

resource "aws_placement_group" "example" {
  name     = "ec2-placement-group-${random_string.suffix.result}"
  strategy = "cluster"
}

resource "aws_instance" "jumphost" {
  ami           = data.aws_ami.amzn2023.id
  instance_type = "t2.micro"
  private_ip    = element(split("/", aws_ec2_subnet_cidr_reservation.jumphost.cidr_block), 0)
  subnet_id     = aws_subnet.private.id

  vpc_security_group_ids = [
    aws_security_group.jumphost.id
  ]

  user_data = <<-EOF
              #!/bin/bash -xe
              hostnamectl set-hostname jumphost
              sudo yum install -y nc
              EOF

  tags = {
    Name = "ec2-placement-group-jh-${random_string.suffix.result}"
  }
}

resource "aws_instance" "webserver" {
  ami             = data.aws_ami.amzn2023.id
  instance_type   = "c5.large"
  placement_group = aws_placement_group.example.name
  private_ip                  = element(split("/", aws_ec2_subnet_cidr_reservation.webserver.cidr_block), 0)
  subnet_id = aws_subnet.public.id

  user_data = <<-EOF
              #!/bin/bash -xe
              hostnamectl set-hostname webserver
              yum update -y
              yum install -y nc nginx
              systemctl start nginx
              systemctl enable nginx
              echo "<h1>Hello, World from $(hostname -f)</h1>" > /usr/share/nginx/html/index.html
              EOF

  vpc_security_group_ids = [
    aws_security_group.webserver.id
  ]

  tags = {
    Name = "ec2-placement-group-ws-${random_string.suffix.result}"
  }
}

output "ec2-placement-group" {
  value = {
    jumphost_pip  = aws_instance.jumphost.public_ip
    jumphost_pvt  = aws_instance.jumphost.private_ip
    webserver_pip = aws_instance.webserver.public_ip
    webserver_pvt = aws_instance.webserver.private_ip
  }
}
