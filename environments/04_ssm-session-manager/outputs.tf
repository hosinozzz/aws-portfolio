output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_id" {
  description = "プライベートサブネット ID"
  value       = aws_subnet.private.id
}

output "production_instance_id" {
  description = "本番EC2インスタンス ID（Session Manager接続に使用）"
  value       = aws_instance.production.id
}

output "staging_instance_id" {
  description = "ステージングEC2インスタンス ID"
  value       = aws_instance.staging.id
}

output "ssm_log_bucket_name" {
  description = "SSMセッションログ保存用S3バケット名"
  value       = aws_s3_bucket.ssm_logs.bucket
}

output "production_access_group_name" {
  description = "productionアクセスグループ名"
  value       = aws_iam_group.production_access.name
}

output "session_manager_connect_production" {
  description = "本番EC2へのSession Manager接続コマンド"
  value       = "aws ssm start-session --target ${aws_instance.production.id} --region ${var.aws_region}"
}

output "session_manager_connect_staging" {
  description = "ステージングEC2へのSession Manager接続コマンド（production-access-groupのユーザーは拒否される）"
  value       = "aws ssm start-session --target ${aws_instance.staging.id} --region ${var.aws_region}"
}

output "jump_server_public_ip" {
  description = "デバッグ用ジャンプサーバーのパブリックIP"
  value       = aws_instance.jump.public_ip
}
