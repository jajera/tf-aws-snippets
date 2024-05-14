resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "ec2-image-template-${random_string.suffix.result}"
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
  name   = "ec2-image-template-${random_string.suffix.result}"
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
    Name = "ec2-image-template-${random_string.suffix.result}"
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

resource "aws_instance" "example" {
  ami                         = data.aws_ami.amzn2023.id
  associate_public_ip_address = false
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private.id

  vpc_security_group_ids = [
    aws_security_group.example.id
  ]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    tags = {
      Name = "root-${random_string.suffix.result}"
    }
  }

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
              # /opt
              if ! blkid /dev/xvdi >/dev/null 2>&1; then
                mkfs -t ext4 /dev/xvdi
                echo "mkfs command has been executed."
                mkfs -t ext4 /dev/xvdi
                mkdir /opt1
                mount /dev/xvdi /opt1
                cp -r /opt/* /opt1
                umount /opt1
                bash -c 'echo "/dev/xvdi /opt ext4 defaults 0 2" >> /etc/fstab'
                mount /opt
                rm -rf /opt1
              else
                echo "File system already exists or is not recognized."
              fi
              EOF

  tags = {
    Name = "ec2-image-template-${random_string.suffix.result}"
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

resource "aws_ebs_volume" "opt" {
  availability_zone = aws_instance.example.availability_zone
  size              = 10

  tags = {
    Name = "opt-${random_string.suffix.result}"
  }
}

resource "aws_volume_attachment" "opt" {
  device_name = "/dev/sdi"
  volume_id   = aws_ebs_volume.opt.id
  instance_id = aws_instance.example.id

  depends_on = [
    aws_instance.example,
    aws_ebs_volume.opt
  ]
}

resource "null_resource" "wait" {
  provisioner "local-exec" {
    command = "sleep 30"
  }

  depends_on = [
    aws_volume_attachment.var,
    aws_volume_attachment.opt,
  ]
}

resource "aws_ami_from_instance" "example" {
  name               = "ec2-custom-${random_string.suffix.result}"
  source_instance_id = aws_instance.example.id

  depends_on = [
    null_resource.wait
  ]
}

resource "aws_instance" "custom" {
  ami                         = aws_ami_from_instance.example.id
  associate_public_ip_address = false
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private.id

  vpc_security_group_ids = [
    aws_security_group.example.id
  ]

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    tags = {
      Name = "root-${random_string.suffix.result}"
    }
  }

  tags = {
    Name = "ec2-custom-${random_string.suffix.result}"
  }
}
