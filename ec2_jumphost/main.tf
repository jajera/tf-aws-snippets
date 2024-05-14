resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_vpc" "example" {
  assign_generated_ipv6_cidr_block = true
  cidr_block                       = "10.0.0.0/16"
  enable_dns_hostnames             = true
  enable_dns_support               = true

  tags = {
    Name = "ec2_jumphost-${random_string.suffix.result}"
  }
}

resource "aws_subnet" "admin" {
  vpc_id     = aws_vpc.example.id
  cidr_block = "10.0.1.0/24"

  tags = {
    Name = "admin"
  }
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.example.id
  cidr_block = "10.0.2.0/24"

  tags = {
    Name = "public"
  }
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.example.id
  cidr_block = "10.0.3.0/24"

  tags = {
    Name = "private"
  }
}

resource "aws_security_group" "admin" {
  name   = "ec2_jumphost-admin-${random_string.suffix.result}"
  vpc_id = aws_vpc.example.id

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "private" {
  name   = "ec2_jumphost-${random_string.suffix.result}"
  vpc_id = aws_vpc.example.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    from_port        = -1
    to_port          = -1
    protocol         = "icmp"
    cidr_blocks      = ["10.0.0.0/16"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = -1
    to_port          = -1
    protocol         = "icmp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
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

resource "aws_route_table" "admin" {
  vpc_id = aws_vpc.example.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.example.id
  }

  tags = {
    Name = "admin"
  }
}

resource "aws_route_table_association" "admin" {
  subnet_id      = aws_subnet.admin.id
  route_table_id = aws_route_table.admin.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example.id
  }

  tags = {
    Name = "public"
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

  tags = {
    Name = "private"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_ec2_instance_connect_endpoint" "example" {
  subnet_id = aws_subnet.private.id

  tags = {
    Name = "ec2_jumphost-${random_string.suffix.result}"
  }
}

data "aws_ami" "amzn2" {
  most_recent = true

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}

resource "tls_private_key" "example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "example" {
  key_name   = "key1"
  public_key = tls_private_key.example.public_key_openssh
}

resource "aws_instance" "jumphost" {
  ami                         = data.aws_ami.amzn2.id
  associate_public_ip_address = false
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.admin.id

  vpc_security_group_ids = [
    aws_security_group.admin.id
  ]

  user_data = <<-EOF
              #!/bin/bash -xe
              mkdir -p /home/ec2-user/.ssh
              chmod 700 /home/ec2-user/.ssh
              echo "${tls_private_key.example.public_key_openssh} ${aws_key_pair.example.key_name}" > /home/ec2-user/.ssh/authorized_keys
              echo "${tls_private_key.example.public_key_openssh} ${aws_key_pair.example.key_name}" > /home/ec2-user/.ssh/id_rsa_server.pub
              echo "${tls_private_key.example.private_key_pem}" > /home/ec2-user/.ssh/id_rsa_server
              echo "Host 10.0.*" >> /home/ec2-user/.ssh/config
              echo "  User ec2-user" >> /home/ec2-user/.ssh/config
              echo "  IdentityFile /home/ec2-user/.ssh/id_rsa_server" >> /home/ec2-user/.ssh/config
              chmod 600 /home/ec2-user/.ssh/config
              chmod 600 /home/ec2-user/.ssh/id_rsa_server
              chmod 600 /home/ec2-user/.ssh/id_rsa_server.pub
              chmod 600 /home/ec2-user/.ssh/authorized_keys
              chown -R ec2-user:ec2-user /home/ec2-user/.ssh
              EOF

  tags = {
    Name = "ec2_jumphost-jumphost-${random_string.suffix.result}"
  }
}

resource "aws_instance" "node1" {
  ami                         = data.aws_ami.amzn2.id
  associate_public_ip_address = false
  key_name                    = aws_key_pair.example.key_name
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private.id

  vpc_security_group_ids = [
    aws_security_group.private.id
  ]

  tags = {
    Name = "ec2_jumphost-node1-${random_string.suffix.result}"
  }
}

output "artifacts" {
  value = {
    jumphost_dns = aws_instance.jumphost.private_dns
    jumphost_ip = aws_instance.jumphost.private_ip
    node1_dns = aws_instance.node1.private_dns
    node1_ip = aws_instance.node1.private_ip
  }
}
