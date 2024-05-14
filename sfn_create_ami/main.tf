resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
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

resource "aws_vpc" "example" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "sfn-create-ami-${random_string.suffix.result}"
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
  name   = "sfn-create-ami-${random_string.suffix.result}"
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

resource "aws_iam_role" "sfn" {
  name = "ami-creation-${random_string.suffix.result}"
  path = "/service-role/"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "ami_creation" {
  name = "ami-creation-${random_string.suffix.result}"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "ec2:RunInstances",
          "ec2:CreateImage"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Action = [
          "ec2:CreateImage",
          "ec2:DeregisterImage",
          "ec2:RunInstances"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:ec2:${data.aws_region.current.name}::image*"
      },
      {
        Action = [
          "imagebuilder:CreateImage",
          "imagebuilder:DeleteImage",
          "imagebuilder:GetImageRecipe",
          "imagebuilder:ListImages"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:imagebuilder:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:image*"
      },
      {
        Action = [
          "imagebuilder:GetInfrastructureConfiguration",
        ],
        Effect   = "Allow",
        Resource = "arn:aws:imagebuilder:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:infrastructure-configuration/*"
      },
      {
        Action = [
          "ec2:TerminateInstances"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:instance*"
      },
      {
        Action = [
          "ec2:CreateImage"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:ec2:${data.aws_region.current.name}::snapshot*"
      },
      {
        Action = [
          "ec2:DescribeInstances",
          "ec2:CreateTags"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = [
          "ssm:GetParameter"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:ssm:${data.aws_region.current.name}::parameter/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ami_creation" {
  role       = aws_iam_role.sfn.name
  policy_arn = aws_iam_policy.ami_creation.arn
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

resource "aws_sfn_state_machine" "example" {
  name     = "ami-creation-${random_string.suffix.result}"
  role_arn = aws_iam_role.sfn.arn

  definition = jsonencode({
    "Comment" : "A Step Functions state machine that runs an EC2 instance and creates an AMI from that instance.",
    "StartAt" : "DescribeInstances",
    "States" : {
      "CheckIfInstancesExist" : {
        "Choices" : [
          {
            "IsPresent" : true,
            "Next" : "TerminateInstance",
            "Variable" : "$.Instances.Reservations[0]"
          }
        ],
        "Default" : "ReadAmiImageId",
        "Type" : "Choice"
      },
      "DescribeInstances" : {
        "Next" : "CheckIfInstancesExist",
        "Parameters" : {
          "Filters" : [
            {
              "Name" : "tag:Name",
              "Values" : [
                "amzn2-example-${random_string.suffix.result}"
              ]
            },
            {
              "Name" : "instance-state-name",
              "Values" : [
                "pending",
                "running",
                "shutting-down",
                "stopped",
                "stopping"
              ]
            }
          ]
        },
        "Resource" : "arn:aws:states:::aws-sdk:ec2:describeInstances",
        "ResultPath" : "$.Instances",
        "Type" : "Task"
      },
      "ReadAmiImageId" : {
        "Next" : "RunInstance",
        "Parameters" : {
          "Name" : "arn:aws:ssm:${data.aws_region.current.name}::parameter/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
        },
        "Resource" : "arn:aws:states:::aws-sdk:ssm:getParameter",
        "ResultPath" : "$.ParameterResult",
        "Type" : "Task"
      },
      "RunInstance" : {
        "Parameters" : {
          "ImageId.$" : "$.ParameterResult.Parameter.Value",
          "InstanceType" : "t2.micro",
          "MaxCount" : 1,
          "MinCount" : 1,
          "SubnetId" : "${aws_subnet.private.id}",
          "TagSpecifications" : [
            {
              "ResourceType" : "instance",
              "Tags" : [
                {
                  "Key" : "Name",
                  "Value" : "amzn2-example-${random_string.suffix.result}"
                }
              ]
            }
          ]
        },
        "Resource" : "arn:aws:states:::aws-sdk:ec2:runInstances",
        "Type" : "Task",
        "ResultPath" : "$.Instances",
        "Next" : "ListImages"
      },
      "ListImages" : {
        "Type" : "Task",
        "Parameters" : {
          "Filters" : [
            {
              "Name" : "name",
              "Values" : ["${aws_imagebuilder_image_recipe.example.name}"]
            },
            {
              "Name" : "version",
              "Values" : ["${aws_imagebuilder_image_recipe.example.version}"]
            }
          ]
        },
        "Resource" : "arn:aws:states:::aws-sdk:imagebuilder:listImages",
        "ResultPath": "$.ListImagesOutput",
        "Next" : "CheckIfImageExist"
      },
      "CheckIfImageExist" : {
        "Choices" : [
          {
            "IsPresent" : true,
            "Next" : "DeleteImage",
            "Variable" : "$.ListImagesOutput.ImageVersionList[0]"
          }
        ],
        "Default" : "CreateImage",

        "Type" : "Choice"
      },
      "DeleteImage" : {
        "Type" : "Task",
        "Parameters" : {
          "ImageBuildVersionArn" : "arn:aws:imagebuilder:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:image/${aws_imagebuilder_image_recipe.example.name}/${aws_imagebuilder_image_recipe.example.version}/1"
        },
        "Resource" : "arn:aws:states:::aws-sdk:imagebuilder:deleteImage",
        "Next" : "CreateImage"
      },
      "CreateImage" : {
        "Type" : "Task",
        "End" : true,
        "Parameters" : {
          "ImageRecipeArn" : "${aws_imagebuilder_image_recipe.example.arn}",
          "InfrastructureConfigurationArn" : "${aws_imagebuilder_infrastructure_configuration.example.arn}",
          "ClientToken.$" : "States.UUID()"
        },
        "Resource" : "arn:aws:states:::aws-sdk:imagebuilder:createImage"
      },
      "TerminateInstance" : {
        "Next" : "ReadAmiImageId",
        "Parameters" : {
          "InstanceIds.$" : "$.Instances.Reservations[*].Instances[*].InstanceId"
        },
        "Resource" : "arn:aws:states:::aws-sdk:ec2:terminateInstances",
        "ResultPath" : "$.TerminatingInstances",
        "Type" : "Task"
      }
    }
  })
}
