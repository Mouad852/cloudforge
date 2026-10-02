variable "region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "eu-west-3"
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget in USD, measured before credits. Set close to the credit left, so the 50/80/95% alerts arrive while it still lasts"
  type        = string
  default     = "60"
}

variable "budget_alert_email" {
  description = "Email address the budget alerts go to. Not committed: pass it with -var or in the gitignored terraform.tfvars"
  type        = string
}
