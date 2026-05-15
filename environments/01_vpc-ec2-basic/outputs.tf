output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "パブリックサブネット ID"
  value       = aws_subnet.public.id
}

output "internet_gateway_id" {
  description = "インターネットゲートウェイ ID"
  value       = aws_internet_gateway.main.id
}

output "security_group_id" {
  description = "セキュリティグループ ID"
  value       = aws_security_group.ec2.id
}

output "instance_id" {
  description = "EC2 インスタンス ID"
  value       = aws_instance.main.id
}

output "instance_public_ip" {
  description = "EC2 パブリック IP アドレス"
  value       = aws_instance.main.public_ip
}

output "instance_public_dns" {
  description = "EC2 パブリック DNS 名"
  value       = aws_instance.main.public_dns
}
