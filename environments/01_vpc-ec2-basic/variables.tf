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

variable "vpc_cidr" {
  description = "VPCのCIDRブロック"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "パブリックサブネットのCIDRブロック"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "アベイラビリティゾーン"
  type        = string
  default     = "ap-northeast-1a"
}

variable "instance_type" {
  description = "EC2インスタンスタイプ（Free Tier: t2.micro）"
  type        = string
  default     = "t2.micro"
}

variable "key_name" {
  description = "SSH接続に使用するキーペア名"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "SSH接続を許可するCIDR（自身のIPを指定すること）"
  type        = string
  default     = "0.0.0.0/0"
}
