# The project's cost alarm (M10). Created in the console in M0 and imported
# here, because as created it could never fire: it included credits, and on the
# AWS Free plan credits cover every charge, so its "actual spend" stayed at 0
# while September cost 113 USD before credits. The three CloudWatch billing
# alarms are blind for the same reason (EstimatedCharges is 0 every day). This
# budget measures cost before credits, so it tracks what the credit balance
# actually loses.
#
# The name is kept from the console: renaming a budget replaces it.
import {
  to = aws_budgets_budget.monthly
  id = "${local.account_id}:cloudforge-monthly-credit"
}

resource "aws_budgets_budget" "monthly" {
  name         = "cloudforge-monthly-credit"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_types {
    include_credit = false
  }

  # Alerts on what has been spent, and one on the forecast, which warns while
  # there is still time to tear something down.
  dynamic "notification" {
    for_each = [50, 80, 95]
    content {
      notification_type          = "ACTUAL"
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      subscriber_email_addresses = [var.budget_alert_email]
    }
  }

  notification {
    notification_type          = "FORECASTED"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
