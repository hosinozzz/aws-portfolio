variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "project" {
  description = "プロジェクト名（タグに使用）"
  type        = string
  default     = "aws-portfolio"
}

variable "environment" {
  description = "環境名（タグに使用）"
  type        = string
  default     = "dev"
}

variable "alert_email" {
  description = "請求アラートの送信先メールアドレス"
  type        = string
  sensitive   = true
}

variable "budget_limit_usd" {
  description = "月次予算の上限額（USD）"
  type        = string
  default     = "1.0"
}

variable "warning_threshold_percentage" {
  description = "早期警告アラートを送信する予算消費率（%）"
  type        = number
  default     = 80
}
