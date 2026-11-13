variable "enable_budget" {
  description = "Create the AWS Budget. Set false in sandbox accounts where an Organization SCP denies AWS Budgets."
  type        = bool
  default     = true
}

variable "aws_region" {
  description = "Region for SNS, Lambda and CloudWatch Logs. Must be the region your lab EC2 instances run in."
  type        = string
  default     = "us-east-1"
}

variable "aws_profile" {
  description = "Local AWS CLI profile. Leave null in GitHub Actions, where credentials come from repository secrets."
  type        = string
  default     = null
}

variable "project_name" {
  description = "Prefix for resource names."
  type        = string
  default     = "cost-guardian"
}

variable "alert_email" {
  description = "Email address that receives budget alerts. You must confirm the subscription email."
  type        = string
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget in USD."
  type        = number
  default     = 10

  validation {
    condition     = var.monthly_budget_usd > 0
    error_message = "monthly_budget_usd must be greater than 0."
  }
}

variable "warning_thresholds_percent" {
  description = "ACTUAL spend percentages that send an email warning only."
  type        = list(number)
  default     = [50, 80]
}

variable "action_threshold_percent" {
  description = "Spend percentage (actual or forecasted) that triggers the Lambda to stop tagged instances."
  type        = number
  default     = 100
}

variable "autostop_tag_key" {
  description = "Tag key that opts an EC2 instance in to being stopped."
  type        = string
  default     = "AutoStop"
}

variable "autostop_tag_value" {
  description = "Tag value that opts an EC2 instance in to being stopped."
  type        = string
  default     = "true"
}

variable "dry_run" {
  description = "When true, the Lambda only logs which instances it would stop."
  type        = bool
  default     = false
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the Lambda."
  type        = number
  default     = 14
}
