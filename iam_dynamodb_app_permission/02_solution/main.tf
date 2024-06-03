locals {
  private_subnet_id = data.terraform_remote_state.example.outputs.private_subnet_id
  public_subnet_id  = data.terraform_remote_state.example.outputs.public_subnet_id
  suffix            = data.terraform_remote_state.example.outputs.suffix
  vpc_id            = data.terraform_remote_state.example.outputs.vpc_id
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

data "aws_vpc" "example" {
  id = local.vpc_id
}

data "aws_subnet" "private" {
  id = local.private_subnet_id
}

data "aws_subnet" "public" {
  id = local.public_subnet_id
}

resource "aws_security_group" "ssh" {
  name   = "iam-dynamodb-app-permission-ssh-${local.suffix}"
  vpc_id = data.aws_vpc.example.id

  ingress {
    description = "ssh from local subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [data.aws_subnet.private.cidr_block]
  }

  ingress {
    description = "ssh from anywhere" # for testing only. apply granular filter
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

  tags = {
    Name = "iam-dynamodb-app-permission-${local.suffix}"
  }
}

resource "aws_security_group" "http" {
  name   = "iam-dynamodb-app-permission-http-${local.suffix}"
  vpc_id = data.aws_vpc.example.id

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
    Name = "iam-dynamodb-app-permission-http-${local.suffix}"
  }
}

data "aws_dynamodb_table" "example" {
  name = "iam-dynamodb-app-permission-${local.suffix}"
}

resource "aws_iam_role" "ec2_dynamodb_read_access" {
  name               = "iam-dynamodb-app-permission-read-${local.suffix}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role" "ec2_dynamodb_write_access" {
  name               = "iam-dynamodb-app-permission-write-${local.suffix}"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "dynamodb_read_access" {
  name        = "DynamoDBReadAccess"
  description = "Policy to allow DynamoDB read access"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "dynamodb:GetItem",
          "dynamodb:BatchGetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ],
        Resource = data.aws_dynamodb_table.example.arn
      }
    ]
  })
}

resource "aws_iam_policy" "dynamodb_write_access" {
  name        = "DynamoDBWriteAccess"
  description = "Policy to allow DynamoDB write access"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ],
        Resource = data.aws_dynamodb_table.example.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_dynamodb_rr_access" {
  role       = aws_iam_role.ec2_dynamodb_read_access.name
  policy_arn = aws_iam_policy.dynamodb_read_access.arn
}

resource "aws_iam_role_policy_attachment" "ec2_dynamodb_wr_access" {
  role       = aws_iam_role.ec2_dynamodb_write_access.name
  policy_arn = aws_iam_policy.dynamodb_read_access.arn
}

resource "aws_iam_role_policy_attachment" "ec2_dynamodb_ww_access" {
  role       = aws_iam_role.ec2_dynamodb_write_access.name
  policy_arn = aws_iam_policy.dynamodb_write_access.arn
}

resource "aws_iam_instance_profile" "dynamodb_read_access" {
  name = "iam-dynamodb-app-permission-read-${local.suffix}"
  role = aws_iam_role.ec2_dynamodb_read_access.name
}

resource "aws_iam_instance_profile" "dynamodb_write_access" {
  name = "iam-dynamodb-app-permission-write-${local.suffix}"
  role = aws_iam_role.ec2_dynamodb_write_access.name
}

resource "aws_instance" "jumphost" {
  ami                         = data.aws_ami.amzn2023.id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.dynamodb_write_access.name
  instance_type               = "t2.micro"
  subnet_id                   = data.aws_subnet.private.id

  vpc_security_group_ids = [
    aws_security_group.ssh.id
  ]

  user_data = <<-EOF
              #!/bin/bash -xe
              hostnamectl set-hostname jumphost
              yum update -y
              yum install -y nc mtr

              AddEmployeeToDynamoDB() {
                  local TABLE_NAME="$1"
                  local EMPLOYEE_NAME="$2"
                  local DEPARTMENT="$3"

                  existing_item=$(aws dynamodb scan --table-name "$TABLE_NAME" \
                      --filter-expression "employee = :emp" \
                      --expression-attribute-values "{\":emp\": {\"S\": \"$EMPLOYEE_NAME\"}}" \
                      --projection-expression "employee" \
                      --consistent-read \
                      --query "Items[0]")

                  if [ "$existing_item" == "null" ]; then
                      aws dynamodb put-item --table-name "$TABLE_NAME" \
                          --item "{\"employee\": {\"S\": \"$EMPLOYEE_NAME\"}, \"department\": {\"S\": \"$DEPARTMENT\"}}"
                      echo "Employee '$EMPLOYEE_NAME' added to '$TABLE_NAME' with department '$DEPARTMENT'."
                  else
                      echo "Employee '$EMPLOYEE_NAME' already exists."
                  fi
              }

              AddEmployeeToDynamoDB "${data.aws_dynamodb_table.example.name}" "Bert" "Manufacturing"
              AddEmployeeToDynamoDB "${data.aws_dynamodb_table.example.name}" "Carl" "Accounting"
              AddEmployeeToDynamoDB "${data.aws_dynamodb_table.example.name}" "Jay" "Facilities"
              EOF

  tags = {
    Name = "iam-dynamodb-app-permission-jumphost-${local.suffix}"
  }
}

resource "aws_instance" "appserver" {
  ami                         = data.aws_ami.amzn2023.id
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.dynamodb_read_access.name
  instance_type               = "t2.micro"
  subnet_id                   = data.aws_subnet.public.id

  vpc_security_group_ids = [
    aws_security_group.ssh.id,
    aws_security_group.http.id
  ]

  user_data = <<-EOF
              #!/bin/bash -xe
              hostnamectl set-hostname appserver
              yum update -y
              yum install -y nc mtr httpd

              DATA=$(aws dynamodb scan --table-name "${data.aws_dynamodb_table.example.name}" | jq -r '.Items[] | [.employee.S, .department.S] | @csv' | tr -d '"')

              echo "<html><body><h1>Employee List</h1><table border='1'><tr><th>Name</th><th>Department</th></tr>" > /var/www/html/index.html
              echo "$DATA" | while IFS=, read -r name department; do
                  echo "<tr><td>$name</td><td>$department</td></tr>" >> /var/www/html/index.html
              done
              echo "</table></body></html>" >> /var/www/html/index.html

              systemctl start httpd
              systemctl enable httpd
              EOF

  tags = {
    Name = "iam-dynamodb-app-permission-appserver-${local.suffix}"
  }

  depends_on = [
    aws_instance.jumphost
  ]
}

output "appserver_pub_ip" {
  value = aws_instance.appserver.public_ip
}

output "appserver_pvt_ip" {
  value = aws_instance.appserver.private_ip
}

output "jumphost_pvt_ip" {
  value = aws_instance.jumphost.private_ip
}
