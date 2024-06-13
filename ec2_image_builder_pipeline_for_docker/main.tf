resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "ec2-image-builder-docker-${random_string.suffix.result}"
  }
}

resource "aws_subnet" "private" {
  vpc_id     = aws_vpc.example.id
  cidr_block = "10.0.1.0/24"
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.example.id
  cidr_block = "10.0.2.0/24"
}

resource "aws_security_group" "example" {
  name   = "ec2-image-builder-docker-${random_string.suffix.result}"
  vpc_id = aws_vpc.example.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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

resource "aws_iam_role" "imagebuilder" {
  name = "ec2-image-builder-docker-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "ec2.amazonaws.com"
          ]
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "imagebuilder_ssm" {
  role       = aws_iam_role.imagebuilder.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "imagebuilder_ec2" {
  role       = aws_iam_role.imagebuilder.name
  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder"
}

resource "aws_iam_role_policy_attachment" "imagebuilder_ecr" {
  role       = aws_iam_role.imagebuilder.name
  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds"
}

resource "aws_iam_instance_profile" "example" {
  name = "ec2-image-builder-docker-${random_string.suffix.result}"
  role = aws_iam_role.imagebuilder.name
}

resource "aws_ecr_repository" "example" {
  name         = "ec2-image-builder-docker-${random_string.suffix.result}"
  force_delete = true
}

resource "aws_cloudwatch_log_group" "example" {
  name              = "/aws/imagebuilder/ec2-image-builder-docker-${random_string.suffix.result}"
  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }
}

data "aws_ami" "amzn2_ecs" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

resource "aws_imagebuilder_component" "install_go_latest" {
  name        = "install-go-latest"
  description = "Installs the latest version of Go"
  platform    = "Linux"
  version     = "1.0.0"

  data = <<EOF
name: Install Go latest
description: Install the latest version of Go Programming Language
schemaVersion: 1.0

phases:
  - name: build
    steps:
      - name: InstallGoBinary
        action: ExecuteBash
        inputs:
          commands:
            - yum install -y golang

      - name: CheckGoVersion
        action: ExecuteBash
        inputs:
          commands:
            - which go
            - /usr/bin/go version
            - /usr/bin/go env
EOF
}

resource "aws_imagebuilder_container_recipe" "ecs" {
  name    = "ecs-${random_string.suffix.result}"
  version = "1.0.0"

  component {
    component_arn = "arn:aws:imagebuilder:${data.aws_region.current.name}:aws:component/update-linux/x.x.x"
  }

  # component {
  #   component_arn = "arn:aws:imagebuilder:${data.aws_region.current.name}:aws:component/go-linux/x.x.x"
  # }

  component {
    component_arn = aws_imagebuilder_component.install_go_latest.arn
  }

  container_type           = "DOCKER"
  dockerfile_template_data = <<-EOF
    FROM {{{ imagebuilder:parentImage }}}
    {{{ imagebuilder:environments }}}
    {{{ imagebuilder:components }}}
  EOF

  parent_image      = "arn:aws:imagebuilder:${data.aws_region.current.name}:aws:image/amazon-linux-2023-x86-2023/x.x.x"
  working_directory = "/tmp"

  target_repository {
    repository_name = aws_ecr_repository.example.name
    service         = "ECR"
  }

  instance_configuration {
    image = data.aws_ami.amzn2_ecs.image_id

    block_device_mapping {
      device_name = "/dev/xvda"

      ebs {
        delete_on_termination = true
        encrypted             = false
        volume_size           = 30
        volume_type           = "gp2"
      }

      no_device = false
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.example
  ]
}

resource "aws_imagebuilder_container_recipe" "docker" {
  name    = "docker-${random_string.suffix.result}"
  version = "1.0.0"

  component {
    component_arn = "arn:aws:imagebuilder:${data.aws_region.current.name}:aws:component/update-linux/x.x.x"
  }

  container_type           = "DOCKER"
  dockerfile_template_data = <<-EOF
    FROM {{{ imagebuilder:parentImage }}}
    {{{ imagebuilder:environments }}}
    {{{ imagebuilder:components }}}
  EOF

  parent_image      = "ubuntu:latest"
  working_directory = "/tmp"

  target_repository {
    repository_name = aws_ecr_repository.example.name
    service         = "ECR"
  }

  instance_configuration {
    image = data.aws_ami.amzn2_ecs.image_id

    block_device_mapping {
      device_name = "/dev/xvda"

      ebs {
        delete_on_termination = true
        encrypted             = false
        volume_size           = 30
        volume_type           = "gp2"
      }

      no_device = false
    }
  }
}

resource "aws_imagebuilder_infrastructure_configuration" "example" {
  name                  = "ec2-image-builder-docker-${random_string.suffix.result}"
  instance_profile_name = aws_iam_instance_profile.example.name
  subnet_id             = aws_subnet.private.id

  security_group_ids = [
    aws_security_group.example.id
  ]

  terminate_instance_on_failure = true
}

resource "aws_imagebuilder_distribution_configuration" "example" {
  name = "ec2-image-builder-docker-${random_string.suffix.result}"

  distribution {
    container_distribution_configuration {
      target_repository {
        repository_name = aws_ecr_repository.example.name
        service         = "ECR"
      }
    }
    region = data.aws_region.current.name
  }
}

resource "aws_imagebuilder_image_pipeline" "ecs" {
  name                             = "ecs-${random_string.suffix.result}"
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.example.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.example.arn
  container_recipe_arn             = aws_imagebuilder_container_recipe.ecs.arn
  enhanced_image_metadata_enabled  = false
}

resource "aws_imagebuilder_image_pipeline" "docker" {
  name                             = "docker-${random_string.suffix.result}"
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.example.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.example.arn
  container_recipe_arn             = aws_imagebuilder_container_recipe.docker.arn
  enhanced_image_metadata_enabled  = false
}
