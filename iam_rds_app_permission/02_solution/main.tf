locals {
  db_dns_name       = data.terraform_remote_state.example.outputs.db_dns_name
  db_ip_addr        = data.terraform_remote_state.example.outputs.db_ip_addr
  db_name           = data.terraform_remote_state.example.outputs.db_name
  db_username       = data.terraform_remote_state.example.outputs.db_username
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
  name   = "iam-rds-app-permission-ssh-${local.suffix}"
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
    Name = "iam-rds-app-permission-ssh-${local.suffix}"
  }
}

resource "aws_security_group" "http_ec2" {
  name   = "iam-rds-app-permission-http-ec2-${local.suffix}"
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
    Name = "iam-rds-app-permission-http-ec2-${local.suffix}"
  }
}

resource "aws_iam_role" "ec2" {
  name               = "iam-rds-app-permission-${local.suffix}"
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

resource "aws_iam_policy" "rds_read_write" {
  name        = "RDSReadWrite"
  description = "Allows reading and writing to RDS PostgreSQL"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "rds-db:connect",
        "rds-db:select",
        "rds:DescribeDBInstances",
        "rds:DescribeDBClusters",
        "rds:GenerateDBAuthToken"
      ],
      "Resource": "arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "rds-db:executeStatement",
        "rds-db:executeSql"
      ],
      "Resource": "arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
    }
  ]
}
EOF
}

resource "aws_iam_user" "sysop" {
  name = "sysop-${local.suffix}"
}

resource "aws_iam_user_policy_attachment" "rds_read_write" {
  user       = aws_iam_user.sysop.name
  policy_arn = aws_iam_policy.rds_read_write.arn
}

resource "aws_iam_role_policy_attachment" "rds_read_write" {
  policy_arn = aws_iam_policy.rds_read_write.arn
  role       = aws_iam_role.ec2.name
}

resource "aws_iam_instance_profile" "ec2_rds" {
  name = "iam-rds-app-permission-${local.suffix}"
  role = aws_iam_role.ec2.name
}

data "aws_secretsmanager_secret" "example" {
  name = "iam-rds-app-permission-${local.suffix}"
}

data "aws_secretsmanager_secret_version" "example" {
  secret_id = data.aws_secretsmanager_secret.example.id
}

resource "random_password" "dbuser" {
  length           = 16
  special          = true
  override_special = "_!#%&*()-<=>?[]^_{|}~"
}

resource "aws_secretsmanager_secret" "dbuser" {
  name                    = "iam-rds-app-permission-dbuser-${local.suffix}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "dbuser" {
  secret_id     = aws_secretsmanager_secret.dbuser.id
  secret_string = "{\"password\": \"${random_password.dbuser.result}\"}"
}

resource "aws_instance" "jumphost" {
  ami                         = data.aws_ami.amzn2023.id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2_rds.name
  instance_type               = "t2.micro"
  subnet_id                   = data.aws_subnet.private.id

  vpc_security_group_ids = [
    aws_security_group.ssh.id
  ]

  user_data = <<-EOF
              #!/bin/bash -xe
              hostnamectl set-hostname jumphost
              yum update -y
              yum install -y nc mtr postgresql15

              export PGPASSWORD="${jsondecode(data.aws_secretsmanager_secret_version.example.secret_string)["password"]}"
              export DBUSERPASSWORD="${jsondecode(aws_secretsmanager_secret_version.dbuser.secret_string)["password"]}"
              export PGDATABASE="${local.db_name}"

              psql -h ${local.db_ip_addr} -U ${local.db_username} -d ${local.db_name} -c "
              DO \$\$
              BEGIN
                  IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'employee') THEN
                      CREATE TABLE public.employee (
                          id SERIAL PRIMARY KEY,
                          name VARCHAR(255) NOT NULL
                      );
                  END IF;

                  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dbuser') THEN
                      CREATE ROLE dbuser WITH LOGIN PASSWORD '$DBUSERPASSWORD';
                  END IF;

                  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'dbuser') THEN
                      GRANT CONNECT ON DATABASE "$PGDATABASE" TO dbuser;
                      GRANT USAGE ON SCHEMA public TO dbuser;
                      GRANT SELECT ON ALL TABLES IN SCHEMA public TO dbuser;
                      ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO dbuser;
                  END IF;
              END;
              \$\$;

              INSERT INTO employee (name) SELECT 'Alice' WHERE NOT EXISTS (SELECT 1 FROM employee WHERE name = 'Alice');
              INSERT INTO employee (name) SELECT 'Bob' WHERE NOT EXISTS (SELECT 1 FROM employee WHERE name = 'Bob');
              INSERT INTO employee (name) SELECT 'Charlie' WHERE NOT EXISTS (SELECT 1 FROM employee WHERE name = 'Charlie');
              "

              EMPLOYEES=$(psql -h ${local.db_ip_addr} -U ${local.db_username} -d ${local.db_name} -t -c "SELECT * FROM employee;")
              echo "Employees:"
              echo "$EMPLOYEES"

              DBUSERS=$(psql -h ${local.db_ip_addr} -U ${local.db_username} -d ${local.db_name} -t -c "SELECT rolname FROM pg_roles;")
              echo "DB Users:"
              echo "$DBUSERS"
              EOF

  tags = {
    Name = "iam-rds-app-permission-jumphost-${local.suffix}"
  }
}

resource "aws_instance" "appserver" {
  ami                         = data.aws_ami.amzn2023.id
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_rds.name
  instance_type               = "t2.micro"
  subnet_id                   = data.aws_subnet.public.id

  vpc_security_group_ids = [
    # aws_security_group.ssh.id,
    aws_security_group.http_ec2.id
  ]

  user_data = <<-EOF
              #!/bin/bash -xe
              hostnamectl set-hostname appserver
              yum update -y
              yum install -y nc mtr postgresql15 httpd

              export PGPASSWORD="${jsondecode(aws_secretsmanager_secret_version.dbuser.secret_string)["password"]}"
              export DBUSERNAME="dbuser"
              export PGDATABASE="${local.db_name}"
              export RDSHOST="${local.db_dns_name}"

              EMPLOYEES=$(psql -h $RDSHOST -U $DBUSERNAME -d $PGDATABASE -t -c "SELECT * FROM employee;")
              echo "Employees:"
              echo "$EMPLOYEES"
              echo "<html><body><h1>Employee List</h1><pre>$EMPLOYEES</pre></body></html>" > /var/www/html/index.html

              systemctl start httpd
              systemctl enable httpd
              EOF

  tags = {
    Name = "iam-rds-app-permission-appserver-${local.suffix}"
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

output "db_name" {
  value = local.db_name
}

output "db_username" {
  value = local.db_username
}

output "db_dns_name" {
  value = local.db_dns_name
}

output "db_ip_addr" {
  value = local.db_ip_addr
}

output "jumphost_pvt_ip" {
  value = aws_instance.jumphost.private_ip
}
