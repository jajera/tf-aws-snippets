
resource "aws_sqs_queue" "my_fifo_queue" {
  name                      = "my-fifo-queue.fifo"
  fifo_queue                = true
  content_based_deduplication = true
  visibility_timeout_seconds = 60

  tags = {
    Name        = "MyFIFOQueue"
    Environment = "Production"
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name   = "lambda_policy"
  role   = aws_iam_role.lambda_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "sqs:SendMessage"
        ]
        Effect   = "Allow"
        Resource = aws_sqs_queue.my_fifo_queue.arn
      }
    ]
  })
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/external/lambda/index.mjs"
  output_path = "${path.module}/external/lambda.zip"
}

resource "aws_lambda_function" "send_message_function" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "send_message_function"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "index.handler"
  runtime          = "nodejs20.x"

  environment {
    variables = {
      QUEUE_URL = aws_sqs_queue.my_fifo_queue.id
    }
  }
}

resource "aws_lambda_invocation" "invoke_send_message_function" {
  function_name = aws_lambda_function.send_message_function.function_name
  input = jsonencode({
    messageBody: "Sample message",
    messageGroupId: "Group1" // Pass the MessageGroupId here
  })
}


# resource "random_string" "suffix" {
#   length  = 8
#   special = false
#   upper   = false
# }

# resource "aws_cloudwatch_log_group" "fifo" {
#   name = "/aws/lambda/sqs-fifo-sequencing-${random_string.suffix.result}-fifo"

#   retention_in_days = 1

#   lifecycle {
#     prevent_destroy = false
#   }
#   # depends_on = [
#   #   aws_iam_role_policy_attachment.sqs_cloudwatch_attachment
#   # ]
# }

# resource "aws_sqs_queue" "dlq" {
#   name                      = "${random_string.suffix.result}-dlq.fifo"
#   delay_seconds             = 60
#   max_message_size          = 262144
#   message_retention_seconds = 1209600
#   receive_wait_time_seconds = 0
#   fifo_queue                = true
# }

# resource "aws_sqs_queue" "fifo" {
#   name                        = "${random_string.suffix.result}.fifo"
#   delay_seconds               = 60
#   max_message_size            = 262144
#   message_retention_seconds   = 345600
#   receive_wait_time_seconds   = 0
#   fifo_queue                  = true
#   content_based_deduplication = true

#   redrive_policy = jsonencode({
#     deadLetterTargetArn = aws_sqs_queue.dlq.arn
#     maxReceiveCount     = 4
#   })

#   depends_on = [
#     aws_cloudwatch_log_group.fifo,
#     # aws_iam_role_policy_attachment.sqs_cloudwatch_attachment
#   ]
# }

# resource "aws_iam_role" "lambda_task_sender" {
#   name = "sqs-fifo-sequencing-${random_string.suffix.result}"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [
#       {
#         Action = "sts:AssumeRole"
#         Effect = "Allow"
#         Principal = {
#           Service = "lambda.amazonaws.com"
#         }
#       },
#     ]
#   })
# }

# resource "aws_iam_role_policy" "lambda_task_sender" {
#   role = aws_iam_role.lambda_task_sender.id

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "sqs:SendMessage"
#         ],
#         Resource = aws_sqs_queue.fifo.arn
#       },
#       {
#         Effect = "Allow",
#         Action = [
#           "logs:CreateLogGroup"
#         ],
#         Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
#       },
#       {
#         Effect = "Allow",
#         Action = [
#           "logs:CreateLogStream",
#           "logs:PutLogEvents"
#         ],
#         Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/lambda-task-sender-${random_string.suffix.result}:*"
#       },
#     ]
#   })
# }

# data "template_file" "lambda_task_sender" {
#   template = file("${path.module}/external/lambda/lambda_task_sender.tpl")

#   vars = {
#     queue_url = aws_sqs_queue.fifo.id
#     message_group_id = "default"
#   }
# }

# data "archive_file" "lambda_task_sender" {
#   type        = "zip"
#   output_path = "${path.module}/external/lambda/lambda_task_sender.zip"

#   source {
#     content  = data.template_file.lambda_task_sender.rendered
#     filename = "index.mjs"
#   }
# }

# resource "null_resource" "lambda_zip_cleanup" {
#   provisioner "local-exec" {
#     when    = destroy
#     command = <<-EOT
#       rm -rf "${path.module}/external/lambda/lambda_task_sender.zip"
#     EOT
#   }

#   depends_on = [
#     data.archive_file.lambda_task_sender
#   ]
# }

# resource "aws_lambda_function" "lambda_task_sender" {
#   function_name = "sqs-fifo-sequencing-${random_string.suffix.result}"
#   role          = aws_iam_role.lambda_task_sender.arn
#   filename      = "${path.module}/external/lambda/lambda_task_sender.zip"
#   handler       = "index.handler"
#   runtime       = "nodejs20.x"
#   memory_size   = 128
#   timeout       = 3

#   ephemeral_storage {
#     size = 512
#   }

#   tracing_config {
#     mode = "PassThrough"
#   }

#   depends_on = [
#     aws_cloudwatch_log_group.fifo,
#     data.archive_file.lambda_task_sender
#   ]
# }

# resource "aws_iam_role" "sqs" {
#   name = "sqs-fifo-sequencing-${random_string.suffix.result}"
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect    = "Allow",
#         Principal = { Service = "sqs.amazonaws.com" },
#         Action    = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# resource "aws_iam_policy" "sqs_write_logs" {
#   name = "WriteLogEvents"
#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "logs:CreateLogGroup"
#         ],
#         Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
#       },
#       {
#         Effect = "Allow",
#         Action = [
#           "logs:CreateLogStream",
#           "logs:PutLogEvents"
#         ],
#         Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/lambda-task-sender-${random_string.suffix.result}:*"
#       },
#     ]
#   })
# }

# resource "aws_iam_role_policy" "lambda_task_sender" {
#   role = aws_iam_role.lambda_task_sender.id

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "sqs:SendMessage"
#         ],
#         Resource = aws_sqs_queue.sqs_send_rcv_msg.arn
#       },
#       {
#         Effect = "Allow",
#         Action = [
#           "logs:CreateLogGroup"
#         ],
#         Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
#       },
#       {
#         Effect = "Allow",
#         Action = [
#           "logs:CreateLogStream",
#           "logs:PutLogEvents"
#         ],
#         Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/lambda-task-sender-${random_string.suffix.result}:*"
#       },
#     ]
#   })
# }


# resource "aws_iam_policy" "sqs_policy" {
#   name        = "sqs_policy"
#   path        = "/"
#   description = "Policy for SQS FIFO queues and CloudWatch logs"

#   # Policy document
#   policy = jsonencode({
#     Version   = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "sqs:SendMessage",
#           "sqs:ReceiveMessage",
#           "sqs:DeleteMessage",
#           "sqs:GetQueueAttributes",
#           "sqs:GetQueueUrl"
#         ],
#         Resource = [
#           aws_sqs_queue.fifo.arn,
#           aws_sqs_queue.dlq.arn
#         ]
#       },
#       {
#         Effect = "Allow",
#         Action = [
#           "logs:CreateLogStream",
#           "logs:PutLogEvents"
#         ],
#         Resource = aws_cloudwatch_log_group.sqs_fifo_log_group.arn
#       }
#     ]
#   })
# }


# resource "aws_iam_role_policy_attachment" "sqs_role_policy_attachment" {
#   role       = aws_iam_role.sqs_role.name
#   policy_arn = aws_iam_policy.sqs_policy.arn
# }


# resource "aws_sqs_queue" "fifo" {
#   name                        = "${random_string.suffix.result}.fifo"
#   fifo_queue                  = true
#   content_based_deduplication = true

#   redrive_policy = jsonencode({
#     deadLetterTargetArn = aws_sqs_queue.dlq.arn
#     maxReceiveCount     = 5
#   })
# }

# resource "aws_sqs_queue" "dlq" {
#   name                        = "${random_string.suffix.result}-dlq.fifo"
#   fifo_queue                  = true
#   content_based_deduplication = true
# }

# resource "aws_iam_role" "lambda_execution_role" {
#   name = "lambda_execution_role"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Principal = {
#           Service = "lambda.amazonaws.com"
#         },
#         Action = "sts:AssumeRole"
#       }
#     ]
#   })
# }

# resource "aws_iam_policy" "lambda_policy" {
#   name        = "lambda_policy"
#   description = "Policy to allow Lambda to write logs to CloudWatch and process SQS messages"

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "logs:CreateLogGroup",
#           "logs:CreateLogStream",
#           "logs:PutLogEvents"
#         ],
#         Resource = "*"
#       },
#       {
#         Effect = "Allow",
#         Action = [
#           "sqs:ReceiveMessage",
#           "sqs:DeleteMessage",
#           "sqs:GetQueueAttributes"
#         ],
#         Resource = aws_sqs_queue.fifo.arn
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
#   role       = aws_iam_role.lambda_execution_role.name
#   policy_arn = aws_iam_policy.lambda_policy.arn
# }

# data "template_file" "sqs_lambda" {
#   template = file("${path.module}/external/lambda/index.js")

#   # vars = {
#   #   table_name = "lambda-sqs-send-rcv-msg-${random_string.suffix.result}"
#   # }
# }

# data "archive_file" "sqs_lambda" {
#   type        = "zip"
#   output_path = "${path.module}/external/lambda/sqs_lambda.zip"

#   source {
#     content  = data.template_file.sqs_lambda.rendered
#     filename = "index.js"
#   }
# }

# resource "aws_lambda_function" "lambda_task_receiver" {
#   function_name = "lambda-task-receiver-${random_string.suffix.result}"
#   role          = aws_iam_role.lambda_execution_role.arn
#   filename      = "${path.module}/external/lambda/sqs_lambda.zip"
#   handler       = "index.handler"
#   runtime       = "nodejs20.x"
#   memory_size   = 128
#   timeout       = 3

#   ephemeral_storage {
#     size = 512
#   }

#   tracing_config {
#     mode = "PassThrough"
#   }

#   # depends_on = [
#   #   aws_cloudwatch_log_group.lambda_task_receiver,
#   #   data.archive_file.lambda_task_receiver
#   # ]
# }

# resource "aws_lambda_permission" "lambda_task_receiver" {
#   statement_id  = "AllowExecutionFromSQS"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.lambda_task_receiver.function_name
#   principal     = "sqs.amazonaws.com"
#   source_arn    = aws_sqs_queue.sqs_send_rcv_msg.arn
# }

# resource "aws_lambda_event_source_mapping" "lambda_task_receiver" {
#   event_source_arn = aws_sqs_queue.sqs_send_rcv_msg.arn
#   function_name    = aws_lambda_function.lambda_task_receiver.arn
#   batch_size       = 10
# }



# resource "aws_lambda_function" "sqs_processor" {
#   filename         = "lambda_function_payload.zip"  # Replace with your zip file containing the Lambda function
#   function_name    = "sqs_processor"
#   role             = aws_iam_role.lambda_execution_role.arn
#   handler          = "index.handler"
#   runtime          = "nodejs14.x"
#   source_code_hash = filebase64sha256("lambda_function_payload.zip")

#   environment {
#     variables = {
#       SQS_QUEUE_URL = aws_sqs_queue.fifo_queue.url
#     }
#   }
# }

# resource "aws_lambda_event_source_mapping" "sqs_event_source" {
#   event_source_arn = aws_sqs_queue.fifo_queue.arn
#   function_name    = aws_lambda_function.sqs_processor.arn
# }

# resource "aws_iam_role" "lambda" {
#   name = "sqs-fifo-sequencing-${random_string.suffix.result}"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Action    = "sts:AssumeRole",
#         Effect    = "Allow",
#         Principal = {
#           Service = "lambda.amazonaws.com"
#         }
#       },
#     ]
#   })
# }

# resource "aws_iam_policy" "sqs_exec" {
#   name = "LambdaSQSQueueExecution"

#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Action = [
#           "logs:CreateLogGroup",
#           "logs:CreateLogStream",
#           "logs:PutLogEvents"
#         ],
#         Effect   = "Allow",
#         Resource = "*"
#       },
#       {
#         Action = "sqs:ReceiveMessage",
#         Effect = "Allow",
#         Resource = aws_sqs_queue.example.arn
#       },
#       {
#         Action = "sqs:DeleteMessage",
#         Effect = "Allow",
#         Resource = aws_sqs_queue.example.arn
#       },
#       {
#         Action = "sqs:GetQueueAttributes",
#         Effect = "Allow",
#         Resource = aws_sqs_queue.example.arn
#       }
#     ]
#   })
# }

# resource "aws_iam_role_policy_attachment" "lambda_sqs_exec" {
#   role       = aws_iam_role.lambda.name
#   policy_arn = aws_iam_policy.sqs_exec.arn
# }

# # data "archive_file" "example" {
# #   type        = "zip"
# #   output_path = "${path.module}/external/lambda/lambda_function_payload.zip"
# #   source_file = "${path.module}/external/lambda/index.js"
# # }

# # resource "http" "aws_sdk_min_js" {
# #   url = "https://raw.githubusercontent.com/aws/aws-sdk-js/master/dist/aws-sdk.min.js"
# # }

# data "archive_file" "example" {
#   type        = "zip"
#   source {
#     content  = <<-EOT
#       ${file("${path.module}/external/lambda/index.js")}

#       // Include AWS SDK
#       ${file("${path.module}/external/lambda/aws-sdk.min.js")}
#     EOT
#     filename = "index.js"
#   }
#   output_path = "${path.module}/external/lambda/lambda_function_payload.zip"
# }

# resource "aws_lambda_function" "process_sqs_messages" {
#   filename      = data.archive_file.example.output_path
#   function_name = "process_sqs_messages"
#   role          = aws_iam_role.lambda.arn
#   handler       = "index.handler"
#   runtime       = "nodejs20.x"

#   environment {
#     variables = {
#       QUEUE_URL = aws_sqs_queue.example.id
#     }
#   }
# }

# # resource "aws_lambda_event_source_mapping" "sqs_lambda" {
# #   event_source_arn = aws_sqs_queue.fifo_queue.arn
# #   function_name    = aws_lambda_function.process_sqs_messages.arn
# #   batch_size       = 10
# # }

