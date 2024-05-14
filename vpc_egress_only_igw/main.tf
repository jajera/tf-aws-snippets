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
    Name = "vpc-egress_only-igw-${random_string.suffix.result}"
  }
}

resource "aws_subnet" "admin" {
  vpc_id          = aws_vpc.example.id
  cidr_block      = "10.0.1.0/24"
  ipv6_cidr_block = cidrsubnet(aws_vpc.example.ipv6_cidr_block, 8, 0)

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

resource "aws_subnet" "ipv6" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.3.0/24"
  ipv6_cidr_block         = cidrsubnet(aws_vpc.example.ipv6_cidr_block, 8, 1)
  map_public_ip_on_launch = true

  tags = {
    Name = "ipv6"
  }
}

resource "aws_security_group" "admin" {
  name   = "vpc-egress_only-igw-admin-${random_string.suffix.result}"
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

resource "aws_security_group" "ipv6" {
  name   = "vpc-egress_only-igw-${random_string.suffix.result}"
  vpc_id = aws_vpc.example.id

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["10.0.1.0/24"]
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

resource "aws_egress_only_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "vpc-egress_only-igw-${random_string.suffix.result}"
  }
}

resource "aws_route_table" "admin" {
  vpc_id = aws_vpc.example.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.example.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.example.id
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

resource "aws_route_table" "ipv6" {
  vpc_id = aws_vpc.example.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.example.id
  }

  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.example.id
  }

  tags = {
    Name = "ipv6"
  }
}

resource "aws_route_table_association" "ipv6" {
  subnet_id      = aws_subnet.ipv6.id
  route_table_id = aws_route_table.ipv6.id
}

resource "aws_ec2_instance_connect_endpoint" "example" {
  subnet_id = aws_subnet.public.id

  tags = {
    Name = "vpc-egress_only-igw-${random_string.suffix.result}"
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

resource "aws_instance" "jumphost" {
  ami                         = data.aws_ami.amzn2.id
  associate_public_ip_address = false
  instance_type               = "t2.micro"
  ipv6_address_count          = 1
  subnet_id                   = aws_subnet.admin.id

  vpc_security_group_ids = [
    aws_security_group.admin.id
  ]

  tags = {
    Name = "vpc-egress_only-igw-jumphost-${random_string.suffix.result}"
  }
}

resource "aws_instance" "ipv6" {
  ami                         = data.aws_ami.amzn2.id
  associate_public_ip_address = false
  instance_type               = "t2.micro"
  ipv6_address_count          = 1
  subnet_id                   = aws_subnet.ipv6.id

  vpc_security_group_ids = [
    aws_security_group.ipv6.id
  ]

  tags = {
    Name = "vpc-egress_only-igw-ipv6-${random_string.suffix.result}"
  }
}
