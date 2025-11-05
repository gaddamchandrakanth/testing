provider "aws" {
  region = "us-east-1"
}
resource "aws_sns_topic" "chandu" {
  name = "chandu-testing"
}
resource "aws_sns_topic_subscription" "chandu-testing" {
  endpoint = "gaddamchandrakanth1995@gmail.com"
  protocol = "email"
  topic_arn = aws_sns_topic.chandu.arn
}
resource "aws_sqs_queue" "chandu-sqs" {
  name                      = "chandu-queue"
  delay_seconds             = 20
  max_message_size          = 2048
  message_retention_seconds = 86400
  receive_wait_time_seconds = 10
}
data "aws_iam_policy_document" "test" {
  statement {
    sid    = "First"
    effect = "Allow"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.chandu-sqs.arn]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.chandu.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "test" {
  queue_url = aws_sqs_queue.chandu-sqs.id
  policy    = data.aws_iam_policy_document.test.json
}
