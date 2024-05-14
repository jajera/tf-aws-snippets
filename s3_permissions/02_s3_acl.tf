resource "aws_s3_bucket" "example_02" {
  bucket = "example-s3-acl-${random_string.suffix.result}"
}

resource "aws_s3_bucket_ownership_controls" "example_02" {
  bucket = aws_s3_bucket.example_02.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "example_02" {
  bucket = aws_s3_bucket.example_02.id
  acl    = "private"

  depends_on = [
    aws_s3_bucket_ownership_controls.example_02
  ]
}

resource "aws_s3_object" "example_02" {
  bucket  = aws_s3_bucket.example_02.bucket
  key     = "example.txt"
  content = "This is a test file created from a sample string."
  acl     = "private"
}
