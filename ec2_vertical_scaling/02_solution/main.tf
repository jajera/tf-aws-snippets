locals {
  suffix = data.terraform_remote_state.example.outputs.suffix
  vpc_id = data.terraform_remote_state.example.outputs.vpc_id
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

resource "aws_iam_role" "ec2" {
  name = "ec2-vertical-scaling-${local.suffix}"
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

resource "aws_iam_policy" "ec2" {
  name = "ec2-vertical-scaling-${local.suffix}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "ec2:DescribeInstances",
          "ec2:ModifyInstanceAttribute",
          "ec2:StartInstances",
          "ec2:StopInstances"
        ],
        Effect   = "Allow",
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ec2" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.ec2.arn
}

resource "aws_iam_instance_profile" "ec2" {
  name = "ec2-vertical-scaling-${local.suffix}"
  role = aws_iam_role.ec2.name
}

data "aws_security_group" "ssh" {
  name = "ec2-vertical-scaling-ssh-${local.suffix}"
}

resource "aws_instance" "jumphost" {
  ami                         = data.aws_ami.amzn2023.id
  associate_public_ip_address = false
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnets.private.ids[0]

  vpc_security_group_ids = [
    data.aws_security_group.ssh.id
  ]

  user_data = <<-EOF
              #!/bin/bash -xe
              hostnamectl set-hostname jumphost
              TAG_NAME="ec2-vertical-scaling-app-${local.suffix}"
              TARGET_INSTANCE_TYPE="c5.large"

              INSTANCE_DETAILS=$(aws ec2 describe-instances \
                --filters "Name=tag:Name,Values=$${TAG_NAME}" \
                --query "Reservations[].Instances[].[InstanceId, InstanceType]" \
                --output text)

              if [ -z "$INSTANCE_DETAILS" ]; then
                echo "No instance found with the tag: $${TAG_NAME}"
                exit 1
              fi

              INSTANCE_ID=$(echo "$INSTANCE_DETAILS" | awk '{print $1}')
              INSTANCE_TYPE=$(echo "$INSTANCE_DETAILS" | awk '{print $2}')

              if [ "$INSTANCE_TYPE" == "$TARGET_INSTANCE_TYPE" ]; then
                echo "Instance $INSTANCE_ID is already of type $TARGET_INSTANCE_TYPE. No action needed."
                exit 0
              fi

              aws ec2 stop-instances --instance-ids $INSTANCE_ID
              aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID
              aws ec2 modify-instance-attribute --instance-id $INSTANCE_ID --instance-type "{\"Value\": \"$TARGET_INSTANCE_TYPE\"}"
              aws ec2 start-instances --instance-ids $INSTANCE_ID
              aws ec2 describe-instance-status --instance-ids $INSTANCE_ID
              EOF

  tags = {
    Name = "ec2-vertical-scaling-jumphost-${local.suffix}"
  }
}
