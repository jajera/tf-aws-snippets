resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "ec2-go-sqs-rds-${random_string.suffix.result}"
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
  name   = "ec2-go-sqs-rds-db-${random_string.suffix.result}"
  vpc_id = aws_vpc.example.id

  ingress {
    from_port = 5432
    to_port   = 5432
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
    Name = "ec2-go-sqs-rds-db-${random_string.suffix.result}"
  }
}

resource "aws_security_group" "ssh" {
  name   = "ec2-go-sqs-rds-${random_string.suffix.result}"
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
    Name = "ec2-go-sqs-rds-${random_string.suffix.result}"
  }
}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "ec2-go-sqs-rds-${random_string.suffix.result}"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "ec2-go-sqs-rds-${random_string.suffix.result}"
  }
}

resource "aws_nat_gateway" "example" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "ec2-go-sqs-rds-${random_string.suffix.result}"
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
    Name = "ec2-go-sqs-rds-${random_string.suffix.result}"
  }
}

resource "aws_cloudwatch_log_group" "example" {
  name              = "/aws/sqs-go/ec2-go-sqs-rds-${random_string.suffix.result}"
  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket" "example" {
  bucket        = "ec2-go-sqs-rds-${random_string.suffix.result}"
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
  name                      = "ec2-go-sqs-rds-${random_string.suffix.result}"
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
  name               = "ec2-go-sqs-rds-${random_string.suffix.result}"
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

# resource "aws_iam_role_policy" "cw_loggroup_create_write" {
#   role = aws_iam_role.ec2.id

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "logs:CreateLogGroup"
#         ],
#         Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
#       },
#       {
#         Effect = "Allow",
#         Action = [
#           "logs:CreateLogStream",
#           "logs:DescribeLogStreams",
#           "logs:PutLogEvents"
#         ],
#         Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/sqs-go/ec2-go-sqs-rds-${random_string.suffix.result}:*"
#       }
#     ]
#   })
# }

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

# resource "aws_iam_role_policy" "write_db" {
#   role = aws_iam_role.ec2.id

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "rds-db:connect"
#         ],
#         Resource = "arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_db_instance.example.resource_id}/rds_iam_user"
#       }
#     ]
#   })
# }

resource "aws_iam_role_policy_attachment" "ec2_policy_attachment" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "ec2-go-sqs-rds-${random_string.suffix.result}"
  role = aws_iam_role.ec2.name
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
  name = "ec2-go-sqs-rds-${random_string.suffix.result}"

  subnet_ids = [
    aws_subnet.db1.id,
    aws_subnet.db2.id
  ]
}

resource "aws_db_instance" "example" {
  identifier                          = "postgresdb"
  allocated_storage                   = 5
  db_name                             = "postgresdb"
  engine                              = "postgres"
  engine_version                      = "16"
  instance_class                      = "db.t3.micro"
  iam_database_authentication_enabled = true
  username                            = "dbadmin"
  password                            = random_password.example.result
  skip_final_snapshot                 = true
  db_subnet_group_name                = aws_db_subnet_group.example.name
  port                                = 5432

  vpc_security_group_ids = [
    aws_security_group.psql_db.id
  ]
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

resource "aws_instance" "jumphost" {
  ami                         = data.aws_ami.ubuntu_22_04.id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private.id

  user_data = <<-EOF
              #!/bin/bash -xe
              hostnamectl set-hostname jumphost
              apt-get update -y
              apt-get install -y awscli postgresql-client-14
              export PGPASSWORD="${aws_db_instance.example.password}"
              export PGDATABASE="${aws_db_instance.example.db_name}"
              export DBUSERNAME="${aws_db_instance.example.username}"
              export RDSHOST="${tolist(data.dns_a_record_set.db.addrs)[0]}"

              psql -h $RDSHOST -U $DBUSERNAME -d $PGDATABASE -c "
              DO \$\$
              BEGIN
                  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dbuser') THEN
                      CREATE ROLE rds_iam_user WITH LOGIN;
                  END IF;

                  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dbuser') THEN
                      GRANT rds_iam TO rds_iam_user;
                  END IF;
              END;
              \$\$;
              "
              EOF

  vpc_security_group_ids = [
    aws_security_group.ssh.id
  ]

  tags = {
    Name = "jumphost-${random_string.suffix.result}"
  }
}

resource "aws_instance" "app" {
  ami                         = data.aws_ami.ubuntu_22_04.id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.private.id

  user_data = <<-EOF
              #!/bin/bash -xe
              hostnamectl set-hostname app
              apt-get update -y
              apt-get install -y awscli postgresql-client-14
              export DBUSERNAME="rds_iam_user"
              export PGDATABASE="${aws_db_instance.example.db_name}"
              export RDSHOST="${tolist(data.dns_a_record_set.db.addrs)[0]}"
              export RDSPORT="${aws_db_instance.example.port}"
              export REGION="${data.aws_region.current.name}"

              TOKEN=$(aws rds generate-db-auth-token --hostname $RDSHOST --port $RDSPORT --region $REGION --username $DBUSERNAME)
              PGPASSWORD="$${TOKEN}" psql "host=$${RDSHOST} port=$${RDSHOST} sslmode=verify-full dbname=$${PGDATABASE} user=$${DBUSERNAME}"
              echo $PGPASSWORD
              EOF

  vpc_security_group_ids = [
    aws_security_group.ssh.id
  ]

  tags = {
    Name = "app-${random_string.suffix.result}"
  }

  depends_on = [
    aws_instance.jumphost
  ]
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

# https://repost.aws/knowledge-center/rds-postgresql-connect-using-iam
# psql -h aurorapg-ssl.cfkx5hi8csxj.us-west-2.rds.amazonaws.com -p 5432 "sslmode=verify-full sslrootcert=rds-ca-2019-root.pem dbname=aurora_pg_ssl user=iamuser"

# PGPASSWORD="${TOKEN}" psql "host=${RDSHOST} port=${RDSPORT} sslmode=verify-full sslrootcert=rds-ca-2019-root.pem dbname=${PGDATABASE} user=${DBUSERNAME}"

# PGPASSWORD="${TOKEN}" psql "host=${RDSHOST} port=${RDSPORT} sslmode=require sslrootcert=rds-ca-2019-root.pem dbname=${PGDATABASE} user=${DBUSERNAME}"

# PGPASSWORD="your_password" psql "host=your_rds_host port=5432 sslmode=verify-full sslrootcert=./rds-ca-2019-root.pem dbname=your_dbname user=your_username" -d 5

# psql -h postgresdb.ccml4r0wntcd.ap-southeast-1.rds.amazonaws.com -U dbadmin -d postgresdb

# curl -O https://s3.amazonaws.com/rds-downloads/rds-ca-2019-root.pem

# sudo apt-get install -y postgresql-client

# psql "host=postgresdb.ccml4r0wntcd.ap-southeast-1.rds.amazonaws.com 
#     port=5432 dbname=postgresdb user=rds_iam_user sslrootcert=rds-ca-rsa2048-g1.pem sslmode=verify-full"

# export TOKEN=$(aws rds generate-db-auth-token --hostname $RDSHOST --port 5432 --region us-west-2 --username dbadmin)

# export TOKEN=$(aws rds generate-db-auth-token --hostname postgresdb.ccml4r0wntcd.ap-southeast-1.rds.amazonaws.com --port 5432 --region ap-southeast-1 --username rds_iam_user)

# curl https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem -o rds-ca-cert.pem

# export PGSSLROOTCERT=./rds-ca-cert.pem

# psql "host=postgresdb.ccml4r0wntcd.ap-southeast-1.rds.amazonaws.com dbname=postgresdb sslmode=verify-full sslrootcert=$PGSSLROOTCERT password=$TOKEN"


# psql \"sslmode=verify-full sslrootcert=$PGSSLROOTCERT host=$RDSHOST dbname=mydatabase user=dbadmin password=$TOKEN\"

#       # Correct psql command to use sslrootcert
#       "psql \"sslmode=verify-full sslrootcert=$PGSSLROOTCERT host=${aws_db_instance.postgres.endpoint} dbname=mydatabase user=dbadmin password=mypassword\""

      
#       "psql \"host=${aws_db_instance.postgres.endpoint} dbname=mydatabase sslmode=require sslrootcert=$PGSSLROOTCERT\""

# curl -o /tmp/rds-ca-cert.pem https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem
# export PGSSLROOTCERT=/tmp/rds-ca-cert.pem

# psql \"sslmode=verify-full sslrootcert=$PGSSLROOTCERT host=$RDSHOST dbname=mydatabase user=dbadmin password=$TOKEN\"

# # SELECT name as "Parameter name", setting as value, short_desc FROM pg_settings WHERE name LIKE '%ssl%';

# #              Parameter name             |                  value                  |                               short_desc                                
# # ----------------------------------------+-----------------------------------------+-------------------------------------------------------------------------
# #  ssl                                    | on                                      | Enables SSL connections.
# #  ssl_ca_file                            | /rdsdbdata/rds-metadata/ca-cert.pem     | Location of the SSL certificate authority file.
# #  ssl_cert_file                          | /rdsdbdata/rds-metadata/server-cert.pem | Location of the SSL server certificate file.
# #  ssl_ciphers                            | HIGH:!aNULL:!3DES                       | Sets the list of allowed SSL ciphers.
# #  ssl_crl_dir                            |                                         | Location of the SSL certificate revocation list directory.
# #  ssl_crl_file                           |                                         | Location of the SSL certificate revocation list file.
# #  ssl_dh_params_file                     |                                         | Location of the SSL DH parameters file.
# #  ssl_ecdh_curve                         | prime256v1                              | Sets the curve to use for ECDH.
# #  ssl_key_file                           | /rdsdbdata/rds-metadata/server-key.pem  | Location of the SSL server private key file.
# #  ssl_library                            | OpenSSL                                 | Shows the name of the SSL library.
# #  ssl_max_protocol_version               |                                         | Sets the maximum SSL/TLS protocol version to use.
# #  ssl_min_protocol_version               | TLSv1.2                                 | Sets the minimum SSL/TLS protocol version to use.
# #  ssl_passphrase_command                 |                                         | Command to obtain passphrases for SSL.
# #  ssl_passphrase_command_supports_reload | off                                     | Controls whether ssl_passphrase_command is called during server reload.
# #  ssl_prefer_server_ciphers              | on                                      | Give priority to server ciphersuite order.




# curl -o /tmp/rds-ca-cert.pem https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem

# # Set environment variables
# export PGSSLROOTCERT=/tmp/rds-ca-cert.pem
# export AWS_REGION=ap-southeast-1
# export RDSHOST=postgresdb.ccml4r0wntcd.ap-southeast-1.rds.amazonaws.com:5432

# TOKEN=$(curl -s "http://169.254.169.254/latest/meta-data/iam/security-credentials/$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/)")

# AWS_ACCESS_KEY_ID=$(echo $TOKEN | jq -r '.AccessKeyId')
# AWS_SECRET_ACCESS_KEY=$(echo $TOKEN | jq -r '.SecretAccessKey')
# AWS_SESSION_TOKEN=$(echo $TOKEN | jq -r '.Token')

# export AWS_ACCESS_KEY_ID
# export AWS_SECRET_ACCESS_KEY
# export AWS_SESSION_TOKEN

# # Generate the RDS authentication token
# export TOKEN=$(aws rds generate-db-auth-token --hostname $RDSHOST --port 5432 --region ap-southeast-1 --username rds_iam_user)

# # Connect to the RDS instance using psql
# psql "sslmode=verify-full sslrootcert=$PGSSLROOTCERT host=$RDSHOST dbname=postgresdb user=rds_iam_user password=$TOKEN"


# curl -o /tmp/rds-ca-cert.pem https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem

# # Set environment variables
# PGSSLROOTCERT=/tmp/rds-ca-cert.pem
# AWS_REGION=ap-southeast-1
# RDSHOST=postgresdb.ccml4r0wntcd.ap-southeast-1.rds.amazonaws.com

# # Generate the RDS authentication token
# TOKEN=$(aws rds generate-db-auth-token --hostname $RDSHOST --port 5432 --region $AWS_REGION --username rds_iam_user)

# # Connect to the RDS instance using psql
# PGPASSWORD="${TOKEN}" psql "sslmode=verify-full sslrootcert=${PGSSLROOTCERT} host=${RDSHOST} dbname=mydatabase user=rds_iam_user"


# curl -o /tmp/rds-ca-cert.pem https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem

# PGSSLROOTCERT=/tmp/rds-ca-cert.pem
# AWS_REGION=ap-southeast-1
# RDSHOST=postgresdb.ccml4r0wntcd.ap-southeast-1.rds.amazonaws.com

# TOKEN=$(aws rds generate-db-auth-token --hostname $RDSHOST --port 5432 --region $AWS_REGION --username rds_iam_user)

# PGPASSWORD="${TOKEN}" psql "sslmode=verify-full sslrootcert=${PGSSLROOTCERT} host=${RDSHOST} port=5432 dbname=mydatabase user=rds_iam_user" -d 5


# export TOKEN=$(aws rds generate-db-auth-token --hostname $RDSHOST --port 5432 --region ap-southeast-1 --username dbadmin)
# psql "sslmode=verify-full sslrootcert=$PGSSLROOTCERT host=$RDSHOST dbname=mydatabase user=dbadmin password=$TOKEN"


# sudo apt-get update
# sudo apt-get install -y postgresql-client curl
# curl -o /tmp/rds-ca-cert.pem https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem
# export PGSSLROOTCERT=/tmp/rds-ca-cert.pem
# export AWS_REGION=ap-southeast-1
# export RDSHOST=${aws_db_instance.postgres.endpoint}
# export TOKEN=$(aws rds generate-db-auth-token --hostname $RDSHOST --port 5432 --region ap-southeast-1 --username rds_iam_user)
# psql "host=$RDSHOST dbname=postgresdb user=rds_iam_user password=$TOKEN" -d 5