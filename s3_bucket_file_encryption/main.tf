resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  name = "s3-file-encryption-${random_string.suffix.result}"
}

resource "aws_kms_key" "example" {
  description             = "Example KMS key for SSE-KMS encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_s3_bucket" "example" {
  bucket        = local.name
  force_destroy = true
}

resource "aws_s3_bucket_ownership_controls" "example" {
  bucket = aws_s3_bucket.example.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "example" {
  bucket = aws_s3_bucket.example.id
  acl    = "private"

  depends_on = [
    aws_s3_bucket_ownership_controls.example
  ]
}

# Server-side encryption with Amazon S3 managed keys (SSE-S3)
resource "aws_s3_object" "example_1" {
  bucket                 = aws_s3_bucket.example.bucket
  key                    = "example_1.txt"
  content                = "This is a test file 1."
  acl                    = "private"
  server_side_encryption = "AES256"
}

# Server-side encryption with AWS Key Management Service keys (SSE-KMS)
resource "aws_s3_object" "example_2" {
  bucket     = aws_s3_bucket.example.bucket
  key        = "example_2.txt"
  content    = "This is a test file 2."
  kms_key_id = aws_kms_key.example.arn
}

# Server-side encryption with AWS Key Management Service keys (SSE-KMS)
resource "aws_s3_object" "example_3" {
  key                    = "example_3.txt"
  bucket                 = aws_s3_bucket.example.id
  content                = "This is a test file 3."
  server_side_encryption = "aws:kms"
}
