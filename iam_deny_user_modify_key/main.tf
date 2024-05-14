resource "aws_iam_user" "example" {
  name = "example_user"
}

resource "aws_iam_policy" "allow_password_change" {
  name        = "AllowUserPasswordChange"
  description = "Allows users to change their own passwords."

  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "iam:ChangePassword",
        Resource = "arn:aws:iam::*:user/${aws_iam_user.example.name}"
      }
    ]
  })
}

resource "aws_iam_policy" "deny_access_key_management" {
  name        = "DenyUserAccessKeyManagement"
  description = "Denies users the ability to manage their own access keys."

  policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Effect   = "Deny",
        Action   = [
          "iam:CreateAccessKey",
          "iam:DeleteAccessKey",
          "iam:ListAccessKeys",
          "iam:UpdateAccessKey"
        ],
        Resource = "arn:aws:iam::*:user/${aws_iam_user.example.name}"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "allow_password_change" {
  user       = aws_iam_user.example.name
  policy_arn = aws_iam_policy.allow_password_change.arn
}

resource "aws_iam_user_policy_attachment" "deny_access_key_management" {
  user       = aws_iam_user.example.name
  policy_arn = aws_iam_policy.deny_access_key_management.arn
}
