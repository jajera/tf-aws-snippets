resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_cloudwatch_log_group" "lambda_task_sender" {
  name              = "/aws/lambda/lambda-task-sender-${random_string.suffix.result}"
  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_cloudwatch_log_group" "lambda_task_receiver" {
  name              = "/aws/lambda/lambda-task-receiver-${random_string.suffix.result}"
  retention_in_days = 1

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_sqs_queue" "sqs_send_rcv_msg" {
  name                      = "sqs_send_rcv_msg-${random_string.suffix.result}"
  delay_seconds             = 60
  max_message_size          = 262144
  message_retention_seconds = 345600
  receive_wait_time_seconds = 0
}

resource "aws_sqs_queue_policy" "example" {
  queue_url = aws_sqs_queue.sqs_send_rcv_msg.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "SQSPolicy"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "SQS:SendMessage",
          "SQS:ReceiveMessage"
        ]
        Resource = aws_sqs_queue.sqs_send_rcv_msg.arn
      },
    ]
  })
}

resource "aws_iam_role" "lambda_task_sender" {
  name = "lambda-task-sender-${random_string.suffix.result}"

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

resource "aws_iam_role_policy" "lambda_task_sender" {
  role = aws_iam_role.lambda_task_sender.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "sqs:SendMessage"
        ],
        Resource = aws_sqs_queue.sqs_send_rcv_msg.arn
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup"
        ],
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/lambda-task-sender-${random_string.suffix.result}:*"
      },
    ]
  })
}

resource "aws_iam_role" "lambda_task_receiver" {
  name = "lambda-task-receiver-${random_string.suffix.result}"

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

resource "aws_iam_role_policy" "lambda_task_receiver" {
  role = aws_iam_role.lambda_task_receiver.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage"
        ],
        Resource = aws_sqs_queue.sqs_send_rcv_msg.arn
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup"
        ],
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
      },
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/lambda-task-receiver-${random_string.suffix.result}:*"
      },
      {
        Effect = "Allow",
        Action = [
          "dynamodb:PutItem"
        ],
        Resource = "arn:aws:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/lambda-sqs-send-rcv-msg-${random_string.suffix.result}"
      }
    ]
  })
}

data "template_file" "lambda_task_sender" {
  template = file("${path.module}/external/lambda/lambda_task_sender.tpl")

  vars = {
    queue_url = aws_sqs_queue.sqs_send_rcv_msg.id
  }
}

data "archive_file" "lambda_task_sender" {
  type        = "zip"
  output_path = "${path.module}/external/lambda/lambda_task_sender.zip"

  source {
    content  = data.template_file.lambda_task_sender.rendered
    filename = "index.mjs"
  }
}

resource "null_resource" "lambda_zip_cleanup" {
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      rm -rf "${path.module}/external/lambda/lambda_task_receiver.zip"
      rm -rf "${path.module}/external/lambda/lambda_task_sender.zip"
    EOT
  }

  depends_on = [
    data.archive_file.lambda_task_receiver,
    data.archive_file.lambda_task_sender
  ]
}

resource "aws_lambda_function" "lambda_task_sender" {
  function_name = "lambda-task-sender-${random_string.suffix.result}"
  role          = aws_iam_role.lambda_task_sender.arn
  filename      = "${path.module}/external/lambda/lambda_task_sender.zip"
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  memory_size   = 128
  timeout       = 3

  ephemeral_storage {
    size = 512
  }

  tracing_config {
    mode = "PassThrough"
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_task_sender,
    data.archive_file.lambda_task_sender
  ]
}

resource "aws_dynamodb_table" "example" {
  name           = "lambda-sqs-send-rcv-msg-${random_string.suffix.result}"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

data "template_file" "lambda_task_receiver" {
  template = file("${path.module}/external/lambda/lambda_task_receiver.tpl")

  vars = {
    table_name = "lambda-sqs-send-rcv-msg-${random_string.suffix.result}"
  }
}

data "archive_file" "lambda_task_receiver" {
  type        = "zip"
  output_path = "${path.module}/external/lambda/lambda_task_receiver.zip"

  source {
    content  = data.template_file.lambda_task_receiver.rendered
    filename = "index.mjs"
  }
}

resource "aws_lambda_function" "lambda_task_receiver" {
  function_name = "lambda-task-receiver-${random_string.suffix.result}"
  role          = aws_iam_role.lambda_task_receiver.arn
  filename      = "${path.module}/external/lambda/lambda_task_receiver.zip"
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  memory_size   = 128
  timeout       = 3

  ephemeral_storage {
    size = 512
  }

  tracing_config {
    mode = "PassThrough"
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda_task_receiver,
    data.archive_file.lambda_task_receiver
  ]
}

resource "aws_lambda_permission" "lambda_task_receiver" {
  statement_id  = "AllowExecutionFromSQS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_task_receiver.function_name
  principal     = "sqs.amazonaws.com"
  source_arn    = aws_sqs_queue.sqs_send_rcv_msg.arn
}

resource "aws_lambda_event_source_mapping" "lambda_task_receiver" {
  event_source_arn = aws_sqs_queue.sqs_send_rcv_msg.arn
  function_name    = aws_lambda_function.lambda_task_receiver.arn
  batch_size       = 10
}
