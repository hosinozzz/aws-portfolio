output "nlb_dns_name" {
  description = "NLBのDNS名（curlテスト用: curl http://<dns>:8080）"
  value       = aws_lb.main.dns_name
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "パブリックサブネット ID"
  value       = aws_subnet.public.id
}

output "network_acl_id" {
  description = "Network ACL ID（AWSコンソールで確認用）"
  value       = aws_network_acl.main.id
}

output "cloudwatch_log_group" {
  description = "VPC Flow Logs のCloudWatchロググループ名"
  value       = aws_cloudwatch_log_group.flow_logs.name
}

output "asg_name" {
  description = "Auto Scaling Group 名"
  value       = aws_autoscaling_group.main.name
}
