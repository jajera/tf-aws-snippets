resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "rds-oracle-${random_string.suffix.result}"
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

resource "aws_db_subnet_group" "example" {
  name = "rds-oracle-${random_string.suffix.result}"

  subnet_ids = [
    aws_subnet.db1.id,
    aws_subnet.db2.id
  ]
}

resource "random_password" "example" {
  length           = 16
  special          = true
  override_special = "_!#%*()-<=>?[]^_{|}~"
}

resource "aws_security_group" "example" {
  name   = "rds-oracle-${random_string.suffix.result}"
  vpc_id = aws_vpc.example.id

  ingress {
    from_port   = 1521
    to_port     = 1521
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "example" {
  allocated_storage    = 20
  engine               = "oracle-se2"
  engine_version       = "19.0.0.0.ru-2024-04.rur-2024-04.r1"
  instance_class       = "db.m5.large"
  db_name              = "ORACLE"
  username             = "dbadmin"
  password             = random_password.example.result
  skip_final_snapshot  = true
  db_subnet_group_name = aws_db_subnet_group.example.name
  license_model        = "license-included"
  port                 = 1521

  vpc_security_group_ids = [
    aws_security_group.example.id
  ]
}

resource "aws_sns_topic" "example" {
  name = "rds-oracle-${random_string.suffix.result}"
}

resource "aws_sns_topic_subscription" "example" {
  topic_arn = aws_sns_topic.example.arn
  protocol  = "email"
  endpoint  = "jdcajer@gmail.com"
}

resource "aws_db_event_subscription" "example" {
  name      = "rds-oracle-${random_string.suffix.result}"
  sns_topic = aws_sns_topic.example.arn

  source_type = "db-security-group"
}
