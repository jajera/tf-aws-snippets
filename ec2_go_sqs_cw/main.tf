resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "ec2-iam-go-${random_string.suffix.result}"
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

resource "aws_security_group" "example" {
  name   = "ec2-iam-go-${random_string.suffix.result}"
  vpc_id = aws_vpc.example.id

  ingress {
    description = "ssh from local subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.private.cidr_block]
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
    Name = "ec2-iam-go-${random_string.suffix.result}"
  }
}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "ec2-iam-go-${random_string.suffix.result}"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "ec2-iam-go-${random_string.suffix.result}"
  }
}

resource "aws_nat_gateway" "example" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "ec2-iam-go-${random_string.suffix.result}"
  }

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

  tags = {
    Name = "private"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_ec2_instance_connect_endpoint" "example" {
  subnet_id = aws_subnet.public.id

  tags = {
    Name = "ec2-iam-go-${random_string.suffix.result}"
  }
}

resource "aws_cloudwatch_log_group" "example" {
  name              = "/aws/sqs-go/ec2-iam-go-${random_string.suffix.result}"
  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket" "example" {
  bucket        = "ec2-iam-go-${random_string.suffix.result}"
  force_destroy = true
}

locals {
  go_code = "${path.module}/external"
  files = [
    for file in fileset(local.go_code, "**/*") :
    {
      path = "${local.go_code}/${file}",
      dest = file
    }
  ]
}

resource "aws_s3_object" "example" {
  for_each = { for file in local.files : file.path => file }
  bucket   = aws_s3_bucket.example.id
  key      = each.value.dest
  source   = each.value.path
  etag     = filemd5(each.value.path)
}

resource "aws_s3_bucket_ownership_controls" "example" {
  bucket = aws_s3_bucket.example.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_sqs_queue" "example" {
  name                      = "ec2-iam-go-${random_string.suffix.result}"
  delay_seconds             = 60
  max_message_size          = 262144
  message_retention_seconds = 345600
  receive_wait_time_seconds = 0
}

resource "aws_sqs_queue_policy" "example" {
  queue_url = aws_sqs_queue.example.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "SQSPolicy"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "SQS:SendMessage",
          "SQS:ReceiveMessage"
        ]
        Resource = aws_sqs_queue.example.arn
      },
    ]
  })
}

resource "aws_iam_role" "ec2" {
  name               = "ec2-iam-go-${random_string.suffix.result}"
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

resource "aws_iam_role_policy" "sqs_read_write" {
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueUrl",
          "sqs:ReceiveMessage",
          "sqs:SendMessage"
        ],
        Resource = aws_sqs_queue.example.arn
      }
    ]
  })
}

resource "aws_iam_role_policy" "cw_loggroup_create_write" {
  role = aws_iam_role.ec2.id

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
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sqs-go/ec2-iam-go-${random_string.suffix.result}:*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_read" {
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:ListBucket"
        ],
        Resource = aws_s3_bucket.example.arn
      },
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ],
        Resource = "${aws_s3_bucket.example.arn}/*"
      }
    ]
  })
}


resource "aws_iam_instance_profile" "ec2_s3" {
  name = "ec2-iam-go-${random_string.suffix.result}"
  role = aws_iam_role.ec2.name
}

data "aws_ami" "ubuntu_22_04" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "example" {
  ami                         = data.aws_ami.ubuntu_22_04.id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2_s3.name
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private.id

  user_data = <<-EOF
              #!/bin/bash -xe
              apt-get update -y
              export DEBIAN_FRONTEND=noninteractive
              apt-get install -y awscli

              snap install go --classic
              export PATH=$PATH:/usr/local/go/bin
              rm -f go$${GO_VERSION}.linux-amd64.tar.gz
              go version
              export HOME=/root
              export GOPATH=$HOME/go
              export GOMODCACHE=$GOPATH/pkg/mod
              export GOCACHE=$GOPATH/cache
              mkdir -p $GOPATH $GOMODCACHE $GOCACHE

              set GO111MODULE=on
              go install golang.org/x/tools/gopls@v0.15.3

              # Create workspace and sync code from S3
              mkdir -p ~/workspace
              aws s3 sync s3://${aws_s3_bucket.example.bucket}/gocode ~/workspace/

              # Move to workspace and set up Go module
              cd ~/workspace
              [ ! -f "go.mod" ] && go mod init sendHeartbeat
              go mod tidy
              go mod download

              # Build the Go application
              go build -o /usr/local/bin/sendHeartbeat cmd/sendHeartbeat/main.go

              # Create the systemd service unit file
              cat <<SERVICE_EOF > /etc/systemd/system/sendHeartbeat.service
              [Unit]
              Description=Send Heartbeat Service
              After=network.target

              [Service]
              ExecStart=/usr/local/bin/sendHeartbeat --region ${data.aws_region.current.name} --queue-url ${aws_sqs_queue.example.url} --enable-cloudwatch --log-group ${aws_cloudwatch_log_group.example.name}
              Restart=always
              User=ubuntu
              Group=ubuntu

              [Install]
              WantedBy=multi-user.target
              SERVICE_EOF

              # Reload systemd manager configuration
              systemctl daemon-reload

              # Enable and start the service
              systemctl enable sendHeartbeat.service
              systemctl start sendHeartbeat.service

              # Dummy SQS messages
              aws sqs send-message --region ${data.aws_region.current.name} --queue-url ${aws_sqs_queue.example.url} --message-body "{\"HeartBeat\":{\"ServiceID\":\"producer.server1\",\"SentTime\":\"$(date -u +"%Y-%m-%dT%H:%M:%S.%NZ")\"}}"
              sleep 60
              aws sqs send-message --region ${data.aws_region.current.name} --queue-url ${aws_sqs_queue.example.url} --message-body "{\"HeartBeat\":{\"ServiceID\":\"producer.server1\",\"SentTime\":\"$(date -u +"%Y-%m-%dT%H:%M:%S.%NZ")\"}}"
              sleep 60
              aws sqs send-message --region ${data.aws_region.current.name} --queue-url ${aws_sqs_queue.example.url} --message-body "{\"HeartBeat\":{\"ServiceID\":\"producer.server1\",\"SentTime\":\"$(date -u +"%Y-%m-%dT%H:%M:%S.%NZ")\"}}"
              EOF

  vpc_security_group_ids = [
    aws_security_group.example.id
  ]

  tags = {
    Name = "ec2-iam-go-${random_string.suffix.result}"
  }
}
