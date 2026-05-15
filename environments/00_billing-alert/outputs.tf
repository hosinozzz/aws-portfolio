output "budget_id" {
  description = "AWS Budgets の予算 ID"
  value       = aws_budgets_budget.monthly.id
}

output "budget_name" {
  description = "AWS Budgets の予算名"
  value       = aws_budgets_budget.monthly.name
}

output "budget_limit_usd" {
  description = "設定した月次予算上限額（USD）"
  value       = aws_budgets_budget.monthly.limit_amount
}
