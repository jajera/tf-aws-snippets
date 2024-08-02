resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_cloudwatch_event_rule" "example" {
  name                = "cw-event-sqs-${random_string.suffix.result}"
  schedule_expression = "rate(1 minute)"
  state               = "ENABLED"
}

resource "aws_cloudwatch_event_target" "example" {
  rule      = aws_cloudwatch_event_rule.example.name
  arn       = aws_sqs_queue.example.arn
  target_id = "sqsCwEventRule"

  input_transformer {
    input_template = <<EOF
{
   "messageType":"cron",
   "cronType":"sqs-cw-event-rule"
}
EOF
  }
}

resource "aws_sqs_queue" "example" {
  name                      = "cw-event-sqs-${random_string.suffix.result}"
  delay_seconds             = 90
  max_message_size          = 2048
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10
}

resource "aws_sqs_queue_policy" "example" {
  queue_url = aws_sqs_queue.example.id
  policy    = data.aws_iam_policy_document.example.json
}

data "aws_iam_policy_document" "example" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    actions = [
      "sqs:SendMessage",
    ]

    resources = [
      aws_sqs_queue.example.arn,
    ]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"

      values = [
        aws_cloudwatch_event_rule.example.arn,
      ]
    }
  }
}
