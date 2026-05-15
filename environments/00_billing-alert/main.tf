terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# -------------------------------------------------------
# ローカル変数：共通タグ
# -------------------------------------------------------
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# -------------------------------------------------------
# 月次コスト予算 + メールアラート
# Free Tier: 1アカウントにつき2予算まで無料
# -------------------------------------------------------
resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-${var.environment}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.budget_limit_usd
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  tags = local.common_tags

  # 予算の80%到達時：早期警告
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = var.warning_threshold_percentage
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  # 予算の100%到達時：上限超過アラート
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}
