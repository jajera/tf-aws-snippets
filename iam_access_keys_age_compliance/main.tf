resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "example" {
  bucket        = "iam-acccess-key-age-${random_string.suffix.result}"
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

resource "aws_iam_role" "config" {
  name = "iam-acccess-key-age-config-${random_string.suffix.result}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        },
        "Action" : "sts:AssumeRole",
        "Condition" : {
          "StringEquals" : {
            "AWS:SourceAccount" : data.aws_caller_identity.current.account_id
          }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "config" {
  role = aws_iam_role.config.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:*",
          "sns:*",
          "config:*",
          "ssm:ExecuteAutomation",
          "iam:ListAccessKeys",
          "iam:UpdateAccessKey"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "ssm" {
  name = "iam-acccess-key-age-ssm-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ssm.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "ssm" {
  role = aws_iam_role.ssm.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "iam:UpdateAccessKey"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "lambda" {
  name = "example-${random_string.suffix.result}-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "lambda" {
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "iam:ListUsers",
          "iam:ListAccessKeys",
          "iam:UpdateAccessKey"
        ],
        Resource = "*"
      },
      {
        Effect = "Allow",
        Action = [
          "config:PutEvaluations"
        ],
        Resource = "*"
      }
    ]
  })
}

resource "aws_config_configuration_recorder" "example" {
  name     = "iam-acccess-key-age-${random_string.suffix.result}"
  role_arn = aws_iam_role.config.arn
}

resource "aws_config_delivery_channel" "example" {
  name           = "iam-acccess-key-age-${random_string.suffix.result}"
  s3_bucket_name = "iam-acccess-key-age-${random_string.suffix.result}"

  depends_on = [
    aws_config_configuration_recorder.example
  ]
}

data "template_file" "example" {
  template = file("${path.module}/external/lambda/check_access_key_age.py")
}

data "archive_file" "example" {
  type        = "zip"
  output_path = "${path.module}/external/lambda/check_access_key_age.zip"

  source {
    content  = data.template_file.example.rendered
    filename = "check_access_key_age.py"
  }
}

resource "aws_cloudwatch_log_group" "example" {
  name              = "/aws/lambda/iam-acccess-key-age-${random_string.suffix.result}"
  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_lambda_function" "check_access_key_age" {
  function_name    = "iam-acccess-key-age-${random_string.suffix.result}"
  filename         = "${path.module}/external/lambda/check_access_key_age.zip"
  handler          = "check_access_key_age.lambda_handler"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  source_code_hash = data.archive_file.example.output_base64sha256
  timeout          = 900

  environment {
    variables = {
      MAX_KEY_AGE = "90"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.example
  ]
}

resource "aws_lambda_permission" "allow_config" {
  statement_id  = "AllowExecutionFromConfig"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.check_access_key_age.function_name
  principal     = "config.amazonaws.com"
}

resource "aws_config_config_rule" "access_key_age" {
  name = "iam-acccess-key-age-${random_string.suffix.result}"

  source {
    owner             = "CUSTOM_LAMBDA"
    source_identifier = aws_lambda_function.check_access_key_age.arn

    source_detail {
      event_source = "aws.config"
      message_type = "ConfigurationItemChangeNotification"
    }
  }
}
