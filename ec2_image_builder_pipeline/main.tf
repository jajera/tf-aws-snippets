resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "ec2-image-builder-${random_string.suffix.result}"
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
  name   = "ec2-image-builder-${random_string.suffix.result}"
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
  name = "ec2-image-builder-${random_string.suffix.result}"
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

data "aws_iam_policy" "AmazonSSMManagedInstanceCore" {
  name = "AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "AmazonSSMManagedInstanceCore" {
  role       = aws_iam_role.imagebuilder.name
  policy_arn = data.aws_iam_policy.AmazonSSMManagedInstanceCore.arn
}

data "aws_iam_policy" "EC2InstanceProfileForImageBuilder" {
  name = "EC2InstanceProfileForImageBuilder"
}

resource "aws_iam_role_policy_attachment" "EC2InstanceProfileForImageBuilder" {
  role       = aws_iam_role.imagebuilder.name
  policy_arn = data.aws_iam_policy.EC2InstanceProfileForImageBuilder.arn
}

resource "aws_imagebuilder_image_recipe" "example" {
  name              = "ec2-image-builder-${random_string.suffix.result}"
  parent_image      = "arn:aws:imagebuilder:${data.aws_region.current.name}:aws:image/amazon-linux-2-x86/x.x.x"
  version           = "1.0.0"
  working_directory = "/tmp"

  component {
    component_arn = "arn:aws:imagebuilder:${data.aws_region.current.name}:aws:component/amazon-cloudwatch-agent-linux/x.x.x"
  }

  component {
    component_arn = "arn:aws:imagebuilder:${data.aws_region.current.name}:aws:component/update-linux/x.x.x"
  }

  component {
    component_arn = "arn:aws:imagebuilder:${data.aws_region.current.name}:aws:component/simple-boot-test-linux/x.x.x"
  }
}

resource "aws_iam_instance_profile" "example" {
  name = "ec2-image-builder-${random_string.suffix.result}"
  role = aws_iam_role.imagebuilder.name
}

resource "aws_imagebuilder_infrastructure_configuration" "example" {
  name = "ec2-image-builder-${random_string.suffix.result}"

  instance_types = [
    "t2.micro",
  ]

  security_group_ids = [
    aws_vpc.example.default_security_group_id
  ]

  subnet_id                     = aws_subnet.private.id
  instance_profile_name         = aws_iam_instance_profile.example.name
  terminate_instance_on_failure = true
}

resource "aws_imagebuilder_distribution_configuration" "example" {
  name = "ec2-image-builder-${random_string.suffix.result}"

  distribution {
    ami_distribution_configuration {

      name = "example-{{ imagebuilder:buildDate }}"

      launch_permission {
        user_ids = [
          data.aws_caller_identity.current.account_id
        ]
      }
    }

    region = data.aws_region.current.name
  }
}

resource "aws_imagebuilder_image_pipeline" "example" {
  name                             = "ec2-image-builder-${random_string.suffix.result}"
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.example.arn
  image_recipe_arn                 = aws_imagebuilder_image_recipe.example.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.example.arn
}
