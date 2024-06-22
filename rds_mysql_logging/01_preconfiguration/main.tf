resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "rds-mysql-logging-${random_string.suffix.result}"
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
  vpc_id     = aws_vpc.example.id
  cidr_block = "10.0.2.0/24"

  tags = {
    Name = "public"
  }
}

resource "aws_subnet" "db1" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = var.availability.zone1

  tags = {
    Name = "db1"
  }
}

resource "aws_subnet" "db2" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = var.availability.zone2

  tags = {
    Name = "db2"
  }
}

resource "aws_security_group" "psql_db" {
  name   = "rds-mysql-logging-db-${random_string.suffix.result}"
  vpc_id = aws_vpc.example.id

  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"
    cidr_blocks = [
      "10.0.1.0/24",
      "10.0.2.0/24"
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-mysql-logging-db-${random_string.suffix.result}"
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

resource "aws_route_table" "db" {
  vpc_id = aws_vpc.example.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.example.id
  }

  tags = {
    Name = "db"
  }
}

resource "aws_route_table_association" "db1" {
  subnet_id      = aws_subnet.db1.id
  route_table_id = aws_route_table.db.id
}

resource "aws_route_table_association" "db2" {
  subnet_id      = aws_subnet.db2.id
  route_table_id = aws_route_table.db.id
}

resource "aws_ec2_instance_connect_endpoint" "example" {
  subnet_id = aws_subnet.public.id

  tags = {
    Name = "rds-mysql-logging-${random_string.suffix.result}"
  }
}

resource "random_password" "example" {
  length           = 16
  special          = true
  override_special = "_!#%&*()-<=>?[]^_{|}~"
}

resource "aws_secretsmanager_secret" "example" {
  name                    = "ec2-go-sqs-rds-${random_string.suffix.result}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "example" {
  secret_id     = aws_secretsmanager_secret.example.id
  secret_string = "{\"password\": \"${random_password.example.result}\"}"
}

resource "aws_db_subnet_group" "example" {
  name = "rds-mysql-logging-${random_string.suffix.result}"

  subnet_ids = [
    aws_subnet.db1.id,
    aws_subnet.db2.id
  ]
}

resource "aws_iam_role" "rds_monitoring" {
  name = "ec2_iam_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "rds_monitoring" {
  role = aws_iam_role.rds_monitoring.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup"
        ],
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"
      }
    ]
  })
}

locals {
  db_name = "mysqldb"
}

resource "aws_cloudwatch_log_group" "rds_audit_logs" {
  name = "/aws/rds/instance/${local.db_name}/audit"

  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_cloudwatch_log_group" "rds_error_logs" {
  name = "/aws/rds/instance/${local.db_name}/error"

  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_cloudwatch_log_group" "rds_general_logs" {
  name = "/aws/rds/instance/${local.db_name}/general"

  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_cloudwatch_log_group" "rds_slowquery_logs" {
  name = "/aws/rds/instance/${local.db_name}/slowquery"

  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_db_instance" "example" {
  identifier                          = local.db_name
  allocated_storage                   = 5
  db_name                             = local.db_name
  engine                              = "mysql"
  engine_version                      = "8.0"
  instance_class                      = "db.t3.micro"
  iam_database_authentication_enabled = true
  multi_az                            = true
  publicly_accessible                 = false
  username                            = "dbadmin"
  password                            = random_password.example.result
  skip_final_snapshot                 = true
  db_subnet_group_name                = aws_db_subnet_group.example.name
  port                                = 3306
  monitoring_interval                 = 60
  monitoring_role_arn                 = aws_iam_role.rds_monitoring.arn

  enabled_cloudwatch_logs_exports = [
    "audit",
    "error",
    "general",
    "slowquery"
  ]

  vpc_security_group_ids = [
    aws_security_group.psql_db.id
  ]

  depends_on = [
    aws_cloudwatch_log_group.rds_audit_logs,
    aws_cloudwatch_log_group.rds_error_logs,
    aws_cloudwatch_log_group.rds_general_logs,
    aws_cloudwatch_log_group.rds_slowquery_logs
  ]
}

output "vpc_id" {
  value = aws_vpc.example.id
}

output "suffix" {
  value = random_string.suffix.result
}

data "dns_a_record_set" "db" {
  host = aws_db_instance.example.address
}

output "db_dns_name" {
  value = aws_db_instance.example.address
}

output "db_ip_addr" {
  value = tolist(data.dns_a_record_set.db.addrs)[0]
}

output "db_name" {
  value = aws_db_instance.example.db_name
}

output "db_username" {
  value = aws_db_instance.example.username
}
