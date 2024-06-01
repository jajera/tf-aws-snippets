resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "ec2-asg-scheduled-scaling-${random_string.suffix.result}"
  }
}

resource "aws_subnet" "private1" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "${data.aws_region.current.name}a"

  tags = {
    Name = "private1"
  }
}

resource "aws_subnet" "private2" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "${data.aws_region.current.name}b"

  tags = {
    Name = "private2"
  }
}

resource "aws_subnet" "private3" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.3.0/24"
  map_public_ip_on_launch = false
  availability_zone       = "${data.aws_region.current.name}c"

  tags = {
    Name = "private3"
  }
}

resource "aws_subnet" "public1" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.4.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${data.aws_region.current.name}a"

  tags = {
    Name = "public1"
  }
}

resource "aws_subnet" "public2" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.5.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${data.aws_region.current.name}b"

  tags = {
    Name = "public2"
  }
}

resource "aws_subnet" "public3" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.6.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${data.aws_region.current.name}c"

  tags = {
    Name = "public3"
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
  subnet_id     = aws_subnet.public1.id

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

  tags = {
    Name = "public"
  }
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

resource "aws_route_table_association" "public1" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public2" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public3" {
  subnet_id      = aws_subnet.public3.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private1" {
  subnet_id      = aws_subnet.private1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private2" {
  subnet_id      = aws_subnet.private2.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private3" {
  subnet_id      = aws_subnet.private3.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "http_alb" {
  name        = "ec2-asg-scheduled-scaling-http-alb-${random_string.suffix.result}"
  description = "Security group for example resources to allow alb access to http"
  vpc_id      = aws_vpc.example.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-asg-scheduled-scaling-http-alb-${random_string.suffix.result}"
  }
}

resource "aws_security_group" "http_ec2" {
  name        = "ec2-asg-scheduled-scaling-http-ec2-${random_string.suffix.result}"
  description = "Security group for example resources to allow access to http hosted in ec2"
  vpc_id      = aws_vpc.example.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.http_alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-asg-scheduled-scaling-http-ec2-${random_string.suffix.result}"
  }
}

resource "aws_lb" "example" {
  name                       = "ec2-asg-${random_string.suffix.result}"
  internal                   = false
  load_balancer_type         = "application"
  enable_deletion_protection = false
  drop_invalid_header_fields = true
  idle_timeout               = 600

  security_groups = [
    aws_security_group.http_alb.id
  ]

  subnets = [
    aws_subnet.public1.id,
    aws_subnet.public2.id,
    aws_subnet.public3.id
  ]
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

resource "aws_launch_template" "example" {
  name_prefix   = "ec2-asg-scheduled-scaling-"
  ebs_optimized = true
  image_id      = data.aws_ami.amzn2023.id
  instance_type = "t3.micro"

  vpc_security_group_ids = [
    aws_security_group.http_ec2.id
  ]

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "ec2-asg-scheduled-scaling-${random_string.suffix.result}"
    }
  }

  user_data = filebase64("${path.module}/external/web.conf")
}

resource "aws_lb_target_group" "example" {
  name        = "ec2-asg-${random_string.suffix.result}"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.example.id

  health_check {
    enabled             = true
    healthy_threshold   = 5
    unhealthy_threshold = 2
    path                = "/"
  }
}

resource "aws_lb_listener" "example" {
  load_balancer_arn = aws_lb.example.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.example.arn
  }
}

resource "aws_autoscaling_group" "example" {
  name_prefix      = "ec2-asg-scheduled-scaling-"
  desired_capacity = 3
  max_size         = 10
  min_size         = 1

  vpc_zone_identifier = [
    aws_subnet.private1.id,
    aws_subnet.private2.id,
    aws_subnet.private3.id
  ]

  target_group_arns = [
    aws_lb_target_group.example.arn
  ]

  launch_template {
    id      = aws_launch_template.example.id
    version = "$Latest"
  }
}

resource "aws_autoscaling_schedule" "scale_up" {
  scheduled_action_name  = "scale-up-daily"
  autoscaling_group_name = aws_autoscaling_group.example.name
  min_size               = 1
  max_size               = 10
  desired_capacity       = 5
  recurrence             = "0 8 * * *" # Scale up at 8 a.m. UTC
}

resource "aws_autoscaling_schedule" "scale_down" {
  scheduled_action_name  = "scale-down-daily"
  autoscaling_group_name = aws_autoscaling_group.example.name
  min_size               = 1
  max_size               = 10
  desired_capacity       = 3
  recurrence             = "0 19 * * *" # Scale down at 7 p.m. UTC
}

output "ec2-asg-scheduled-scaling" {
  value = {
    alb = aws_lb.example.dns_name
  }
}
