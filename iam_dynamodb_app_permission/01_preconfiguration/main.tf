resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "iam-dynamodb-app-permission-${random_string.suffix.result}"
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

resource "aws_ec2_instance_connect_endpoint" "example" {
  subnet_id = aws_subnet.public.id

  tags = {
    Name = "iam-dynamodb-app-permission-${random_string.suffix.result}"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_dynamodb_table" "example" {
  name         = "iam-dynamodb-app-permission-${random_string.suffix.result}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "employee"

  attribute {
    name = "employee"
    type = "S"
  }
}

resource "aws_dynamodb_table_item" "alice" {
  table_name = aws_dynamodb_table.example.name
  hash_key   = aws_dynamodb_table.example.hash_key

  item = <<ITEM
{
  "employee": {"S": "Alice"},
  "department": {"S": "HR"}
}
ITEM
}

resource "aws_dynamodb_table_item" "bob" {
  table_name = aws_dynamodb_table.example.name
  hash_key   = aws_dynamodb_table.example.hash_key

  item = <<ITEM
{
  "employee": {"S": "Bob"},
  "department": {"S": "Sales"}
}
ITEM
}

resource "aws_dynamodb_table_item" "charlie" {
  table_name = aws_dynamodb_table.example.name
  hash_key   = aws_dynamodb_table.example.hash_key

  item = <<ITEM
{
  "employee": {"S": "Charlie"},
  "department": {"S": "IT"}
}
ITEM
}

output "suffix" {
  value = random_string.suffix.result
}

output "vpc_id" {
  value = aws_vpc.example.id
}

output "private_subnet_id" {
  value = aws_subnet.private.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}
