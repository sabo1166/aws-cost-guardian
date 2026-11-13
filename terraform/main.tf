data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# ---------------------------------------------------------------------------
# SNS topics
#   warning topic -> email only (50% / 80% of actual spend)
#   action topic  -> email + Lambda (100% actual or forecasted spend)
# Two topics keep early warnings from stopping anything.
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "warning" {
  name = "${var.project_name}-warning"
}

resource "aws_sns_topic" "action" {
  name = "${var.project_name}-action"
}

# Allow AWS Budgets (from this account only) to publish to both topics.
data "aws_iam_policy_document" "budgets_publish" {
  for_each = {
    warning = aws_sns_topic.warning.arn
    action  = aws_sns_topic.action.arn
  }

  statement {
    sid       = "AllowBudgetsPublish"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [each.value]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "AllowAccountOwnerManage"
    effect    = "Allow"
    actions   = ["SNS:Publish", "SNS:Subscribe", "SNS:GetTopicAttributes", "SNS:SetTopicAttributes"]
    resources = [each.value]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_sns_topic_policy" "warning" {
  arn    = aws_sns_topic.warning.arn
  policy = data.aws_iam_policy_document.budgets_publish["warning"].json
}

resource "aws_sns_topic_policy" "action" {
  arn    = aws_sns_topic.action.arn
  policy = data.aws_iam_policy_document.budgets_publish["action"].json
}

resource "aws_sns_topic_subscription" "warning_email" {
  topic_arn = aws_sns_topic.warning.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "action_email" {
  topic_arn = aws_sns_topic.action.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------
# AWS Budget
# ---------------------------------------------------------------------------

resource "aws_budgets_budget" "monthly" {
  count = var.enable_budget ? 1 : 0

  name         = "${var.project_name}-monthly"
  budget_type  = "COST"
  limit_amount = format("%.2f", var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = var.warning_thresholds_percent
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value
      threshold_type            = "PERCENTAGE"
      notification_type         = "ACTUAL"
      subscriber_sns_topic_arns = [aws_sns_topic.warning.arn]
    }
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = var.action_threshold_percent
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_sns_topic_arns = [aws_sns_topic.action.arn]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = var.action_threshold_percent
    threshold_type            = "PERCENTAGE"
    notification_type         = "FORECASTED"
    subscriber_sns_topic_arns = [aws_sns_topic.action.arn]
  }

  depends_on = [aws_sns_topic_policy.warning, aws_sns_topic_policy.action]
}

# ---------------------------------------------------------------------------
# Lambda: stops running EC2 instances tagged AutoStop=true
# ---------------------------------------------------------------------------

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../lambda/handler.py"
  output_path = "${path.module}/build/handler.zip"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    sid       = "DescribeInstances"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"] # Describe actions do not support resource-level permissions.
  }

  statement {
    sid       = "StopOnlyTaggedInstances"
    actions   = ["ec2:StopInstances"]
    resources = ["arn:aws:ec2:${var.aws_region}:${local.account_id}:instance/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/${var.autostop_tag_key}"
      values   = [var.autostop_tag_value]
    }
  }

  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.project_name}-least-privilege"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_lambda_function" "guardian" {
  function_name    = var.project_name
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.12"
  handler          = "handler.lambda_handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      TAG_KEY   = var.autostop_tag_key
      TAG_VALUE = var.autostop_tag_value
      DRY_RUN   = tostring(var.dry_run)
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy.lambda]
}

resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowActionTopicInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.guardian.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.action.arn
}

resource "aws_sns_topic_subscription" "action_lambda" {
  topic_arn = aws_sns_topic.action.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.guardian.arn

  depends_on = [aws_lambda_permission.allow_sns]
}
