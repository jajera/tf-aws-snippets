
locals {
  suffix = data.terraform_remote_state.example.outputs.suffix
}

data "aws_iam_user" "cwuser" {
  user_name = "cwuser-${local.suffix}"
}

resource "aws_iam_policy" "ec2_stop" {
  name        = "EC2StopPolicy"
  description = "Allows stopping EC2 instances"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ec2:Describe*",
          "ec2:StopInstances"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "ec2_stop" {
  user       = data.aws_iam_user.cwuser.user_name
  policy_arn = aws_iam_policy.ec2_stop.arn
}
