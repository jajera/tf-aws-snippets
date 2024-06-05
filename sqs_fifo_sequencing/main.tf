resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_sqs_queue" "example" {
  name                        = "${random_string.suffix.result}.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
}

resource "aws_iam_role" "lambda" {
  name = "sqs-fifo-sequencing-${random_string.suffix.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "sqs_exec" {
  name = "LambdaSQSQueueExecution"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action = "sqs:ReceiveMessage",
        Effect = "Allow",
        Resource = aws_sqs_queue.example.arn
      },
      {
        Action = "sqs:DeleteMessage",
        Effect = "Allow",
        Resource = aws_sqs_queue.example.arn
      },
      {
        Action = "sqs:GetQueueAttributes",
        Effect = "Allow",
        Resource = aws_sqs_queue.example.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_sqs_exec" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.sqs_exec.arn
}

# data "archive_file" "example" {
#   type        = "zip"
#   output_path = "${path.module}/external/lambda/lambda_function_payload.zip"
#   source_file = "${path.module}/external/lambda/index.js"
# }

# resource "http" "aws_sdk_min_js" {
#   url = "https://raw.githubusercontent.com/aws/aws-sdk-js/master/dist/aws-sdk.min.js"
# }

data "archive_file" "example" {
  type        = "zip"
  source {
    content  = <<-EOT
      ${file("${path.module}/external/lambda/index.js")}

      // Include AWS SDK
      ${file("${path.module}/external/lambda/aws-sdk.min.js")}
    EOT
    filename = "index.js"
  }
  output_path = "${path.module}/external/lambda/lambda_function_payload.zip"
}

resource "aws_lambda_function" "process_sqs_messages" {
  filename      = data.archive_file.example.output_path
  function_name = "process_sqs_messages"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.example.id
    }
  }
}

# resource "aws_lambda_event_source_mapping" "sqs_lambda" {
#   event_source_arn = aws_sqs_queue.fifo_queue.arn
#   function_name    = aws_lambda_function.process_sqs_messages.arn
#   batch_size       = 10
# }

