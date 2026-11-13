output "warning_topic_arn" {
  description = "SNS topic for email-only warnings."
  value       = aws_sns_topic.warning.arn
}

output "action_topic_arn" {
  description = "SNS topic that triggers the guardian Lambda. Publish to it to test."
  value       = aws_sns_topic.action.arn
}

output "lambda_function_name" {
  value = aws_lambda_function.guardian.function_name
}

output "lambda_log_group" {
  value = aws_cloudwatch_log_group.lambda.name
}

output "budget_name" {
  value = aws_budgets_budget.monthly.name
}
