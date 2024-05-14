resource "aws_iam_user" "example_03" {
  name = "example-bucket-access-policy-${random_string.suffix.result}"
}

resource "aws_s3_bucket" "example_03" {
  bucket = "example-bucket-access-policy-${random_string.suffix.result}"
}

resource "aws_s3_bucket_policy" "example_03" {
  bucket = "${aws_s3_bucket.example_03.id}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "${aws_iam_user.example_03.arn}"
      },
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "${aws_s3_bucket.example_03.arn}",
        "${aws_s3_bucket.example_03.arn}/*"
      ]
    }
  ]
}
EOF
}
