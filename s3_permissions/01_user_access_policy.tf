resource "aws_iam_user" "example_01" {
  name = "example-user-access-policy-${random_string.suffix.result}"
}

resource "aws_iam_policy" "s3_access_policy" {
  name        = "example-user-access-policy-${random_string.suffix.result}"
  description = "A policy to allow access to S3"
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "s3:ListBucket",
          "s3:GetObject"
        ],
        "Resource" : [
          "arn:aws:s3:::example-user-access-policy-${random_string.suffix.result}",
          "arn:aws:s3:::example-user-access-policy-${random_string.suffix.result}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "example_01" {
  user       = aws_iam_user.example_01.name
  policy_arn = aws_iam_policy.s3_access_policy.arn
}

resource "aws_s3_bucket" "example_01" {
  bucket = "example-user-access-policy-${random_string.suffix.result}"
}
