resource "aws_dynamodb_table" "example" {
  name           = "example-table"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "Id"

  attribute {
    name = "Id"
    type = "S"
  }

  tags = {
    Application = "demo_app"
  }
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "example" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

resource "aws_network_interface" "example" {
  subnet_id   = aws_subnet.example.id
  private_ips = ["10.0.1.50"]
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

resource "aws_instance" "example" {
  ami           = data.aws_ami.amzn2.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.example.id

  tags = {
    Application = "demo_app"
  }
}

resource "aws_cloudwatch_dashboard" "example" {
  dashboard_name = "example-dashboard"

  dashboard_body = <<EOF
{
  "widgets": [
    {
      "type": "metric",
      "x": 0,
      "y": 0,
      "width": 6,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/EC2", "CPUUtilization", "Application", "demo_app", { "id": "m1", "label": "Application demo_app" } ]
        ],
        "period": 300,
        "stat": "Average",
        "region": "${data.aws_region.current.name}",
        "title": "Average CPU Utilization"
      }
    },
    {
      "type": "metric",
      "x": 7,
      "y": 0,
      "width": 6,
      "height": 6,
      "properties": {
        "metrics": [
          [ "AWS/DynamoDB", "ThrottledRequests", "TableName", "${aws_dynamodb_table.example.name}", { "id": "m1", "label": "Table ${aws_dynamodb_table.example.name}" } ]
        ],
        "period": 300,
        "stat": "Sum",
        "region": "${data.aws_region.current.name}",
        "title": "Total Throttled Requests"
      }
    }
  ]
}
EOF
}
