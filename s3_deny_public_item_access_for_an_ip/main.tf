resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "example" {
  bucket = "example-${random_string.suffix.result}"
}

resource "aws_s3_bucket_policy" "example" {
  bucket = aws_s3_bucket.example.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "IPDeny"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.example.arn}/*"
      Condition = {
        IpAddress = {
          "aws:SourceIp" = ["203.0.113.0/24"]
        }
      }
    }]
  })
}
