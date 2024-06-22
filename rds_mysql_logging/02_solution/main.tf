locals {
  db_dns_name = data.terraform_remote_state.example.outputs.db_dns_name
  db_ip_addr  = data.terraform_remote_state.example.outputs.db_ip_addr
  db_name     = data.terraform_remote_state.example.outputs.db_name
  db_username = data.terraform_remote_state.example.outputs.db_username
  suffix      = data.terraform_remote_state.example.outputs.suffix
  vpc_id      = data.terraform_remote_state.example.outputs.vpc_id
}

data "aws_vpc" "example" {
  id = local.vpc_id
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "tag:Name"
    values = ["private*"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [local.vpc_id]
  }

  filter {
    name   = "tag:Name"
    values = ["public*"]
  }
}

data "http" "my_public_ip" {
  url = "http://ifconfig.me/ip"
}

data "aws_db_instance" "example" {
  db_instance_identifier = local.db_name
}

resource "aws_security_group" "ssh" {
  name   = "rds-mysql-logging-ssh-${local.suffix}"
  vpc_id = data.aws_vpc.example.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${data.http.my_public_ip.response_body}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ec2_rds" {
  name = "rds-mysql-logging-${local.suffix}"
  path = "/service-role/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "ec2_rds" {
  name = "rds-mysql-logging-${local.suffix}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "rds:DescribeDBInstances",
          "rds:DescribeEvents",
          "rds:ModifyDBInstance"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:db:*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_rds" {
  role       = aws_iam_role.ec2_rds.name
  policy_arn = aws_iam_policy.ec2_rds.arn
}

resource "aws_iam_instance_profile" "ec2_rds" {
  name = "rds-mysql-logging-${local.suffix}"
  role = aws_iam_role.ec2_rds.name
}


data "aws_security_group" "ssh" {
  name = "rds-mysql-logging-ssh-${local.suffix}"
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

resource "aws_instance" "jumphost" {
  ami                         = data.aws_ami.amzn2023.id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2_rds.name
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnets.private.ids[0]

  user_data = <<-EOF
              #!/bin/bash -xe
              hostnamectl set-hostname jumphost
              dnf install -y nc mariadb105
                  
              aws rds modify-db-instance \
                  --db-instance-identifier ${data.aws_db_instance.example.db_instance_identifier} \
                  --no-enable-enhanced-monitoring \
                  --apply-immediately

              aws rds modify-db-instance \
                  --db-instance-identifier ${data.aws_db_instance.example.db_instance_identifier} \
                  --cloudwatch-logs-export-configuration '{"EnableLogTypes": [], "DisableLogTypes": ["audit", "error", "general", "slowquery"]}' \
                  --apply-immediately \
                  --no-cli-pager
              
              aws rds wait db-instance-available --db-instance-identifier ${data.aws_db_instance.example.db_instance_identifier}      
              EOF

  vpc_security_group_ids = [
    aws_security_group.ssh.id
  ]

  tags = {
    Name = "rds-mysql-logging-jumphost-${local.suffix}"
  }
}
