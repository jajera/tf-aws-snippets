resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "ec2-cloudwatch-monitoring-${random_string.suffix.result}"
  }
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.example.id
  cidr_block = "10.0.1.0/24"
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.example.id
  cidr_block = "10.0.2.0/24"
}

resource "aws_security_group" "example" {
  name   = "ec2-cloudwatch-monitoring-${random_string.suffix.result}"
  vpc_id = aws_vpc.example.id

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

resource "aws_instance" "example" {
  ami           = data.aws_ami.amzn2023.id
  instance_type = "t2.micro"
  monitoring    = true
  subnet_id     = aws_subnet.private.id

  user_data = <<-EOF
              #!/bin/bash -xe
              sleep 30
              # /var
              if ! blkid /dev/xvdh >/dev/null 2>&1; then
                mkfs -t ext4 /dev/xvdh
                echo "mkfs command has been executed."
                mkfs -t ext4 /dev/xvdh
                mkdir /var1
                mount /dev/xvdh /var1
                cp -r /var/* /var1
                umount /var1
                bash -c 'echo "/dev/xvdh /var ext4 defaults 0 2" >> /etc/fstab'
                mount /var
                rm -rf /var1
              else
                echo "File system already exists or is not recognized."
              fi
              EOF

  tags = {
    Name = "ec2-cloudwatch-monitoring-${random_string.suffix.result}"
  }
}

resource "aws_ebs_volume" "var" {
  availability_zone = aws_instance.example.availability_zone
  size              = 10

  tags = {
    Name = "var-${random_string.suffix.result}"
  }
}

resource "aws_volume_attachment" "var" {
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.var.id
  instance_id = aws_instance.example.id

  depends_on = [
    aws_instance.example,
    aws_ebs_volume.var
  ]
}
