resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "ec2-cw-permission-${random_string.suffix.result}"
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
  name   = "ec2-cw-permission-${random_string.suffix.result}"
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
    Name = "ec2-cw-permission-${random_string.suffix.result}"
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

resource "aws_iam_user" "cwuser" {
  name = "cwuser-${random_string.suffix.result}"
}

resource "aws_iam_policy" "cw_metric_alarm_put" {
  name        = "cw-put-metric-alarm-${random_string.suffix.result}"
  description = "Policy to allow PutMetricAlarm operation in CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "cloudwatch:PutMetricAlarm",
        Resource = "*",
      },
    ],
  })
}

resource "aws_iam_user_policy_attachment" "cw_metric_alarm_put" {
  user       = aws_iam_user.cwuser.name
  policy_arn = aws_iam_policy.cw_metric_alarm_put.arn
}

resource "aws_iam_access_key" "cwuser" {
  user = aws_iam_user.cwuser.name
}

resource "aws_instance" "example" {
  ami                         = data.aws_ami.amzn2023.id
  associate_public_ip_address = false
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private.id

  vpc_security_group_ids = [
    aws_security_group.example.id
  ]

  tags = {
    Name = "ec2-cw-permission-node1-${random_string.suffix.result}"
  }
}

resource "aws_instance" "jumphost" {
  ami                         = data.aws_ami.amzn2023.id
  associate_public_ip_address = false
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private.id

  vpc_security_group_ids = [
    aws_security_group.example.id
  ]

  user_data = <<-EOF
              #!/bin/bash -xe
              mkdir -p /home/ec2-user/.aws

              cat << EOT > /home/ec2-user/.aws/config
              [default]
              region=${data.aws_region.current.name}
              output=json
              EOT

              cat << EOT > /home/ec2-user/.aws/credentials
              [default]
              aws_access_key_id=${aws_iam_access_key.cwuser.id}
              aws_secret_access_key=${aws_iam_access_key.cwuser.secret}
              EOT

              chown -R ec2-user:ec2-user /home/ec2-user/.aws

              sudo -u ec2-user /bin/bash -c 'aws cloudwatch put-metric-alarm \
                --alarm-name stop-instances-alarm \
                --alarm-description "Alarm to stop instances when CPU utilization is less than or equal to 10%" \
                --metric-name CPUUtilization \
                --namespace AWS/EC2 \
                --statistic Average \
                --period 300 \
                --evaluation-periods 1 \
                --threshold 10 \
                --comparison-operator LessThanOrEqualToThreshold \
                --dimensions Name=InstanceId,Value=${aws_instance.example.id} \
                --alarm-actions arn:aws:automate:${data.aws_region.current.name}:ec2:stop'
              EOF

  tags = {
    Name = "ec2-cw-permission-jh-${random_string.suffix.result}"
  }
}

resource "null_resource" "cw_metric_alarm" {
  triggers = {
    region = data.aws_region.current.name
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      unset AWS_VAULT
      aws-vault exec dev -- aws cloudwatch delete-alarms \
        --alarm-names stop-instances-alarm \
        --region ${self.triggers.region}
    EOT
  }
}

output "suffix" {
  value = random_string.suffix.result
}
