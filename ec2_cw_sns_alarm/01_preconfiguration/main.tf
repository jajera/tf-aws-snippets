resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "ec2-cw-sns-alarm-${random_string.suffix.result}"
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
  name   = "ec2-cw-sns-alarm-${random_string.suffix.result}"
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
    Name = "ec2-cw-sns-alarm-${random_string.suffix.result}"
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

  tags = {
    Name = "ec2-cw-sns-alarm-${random_string.suffix.result}"
  }
}

resource "aws_sns_topic" "example" {
  name = "ec2-cw-sns-alarm-${random_string.suffix.result}"
}

resource "aws_sns_topic_subscription" "example" {
  topic_arn = aws_sns_topic.example.arn
  protocol  = "email"
  endpoint  = "jdcajer@gmail.com"
}

resource "aws_cloudwatch_metric_alarm" "example" {
  alarm_name          = "HighCPUUtilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300"
  statistic           = "Average"
  threshold           = "50"
  alarm_description   = "This metric monitors EC2 CPU utilization"
  
  dimensions = {
    InstanceId = aws_instance.example.id
  }
  
  alarm_actions       = [
    aws_sns_topic.example.arn
  ]
}

output "instance_id" {
  value = aws_instance.example.id
}

locals {
  alarm_attributes = {
    alarm_description   = aws_cloudwatch_metric_alarm.example.alarm_description
    alarm_name          = aws_cloudwatch_metric_alarm.example.alarm_name
    comparison_operator = aws_cloudwatch_metric_alarm.example.comparison_operator
    dimensions          = aws_cloudwatch_metric_alarm.example.dimensions
    evaluation_periods  = aws_cloudwatch_metric_alarm.example.evaluation_periods
    metric_name         = aws_cloudwatch_metric_alarm.example.metric_name
    namespace           = aws_cloudwatch_metric_alarm.example.namespace
    period              = aws_cloudwatch_metric_alarm.example.period
    statistic           = aws_cloudwatch_metric_alarm.example.statistic
    threshold           = aws_cloudwatch_metric_alarm.example.threshold
  }
}

output "cloudwatch_metric_alarm" {
  value = local.alarm_attributes
}
