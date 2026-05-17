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
# ローカル変数：共通タグ・ユーザーデータ
# -------------------------------------------------------
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  user_data = <<-EOT
    #!/bin/bash
    mkdir -p /var/www/html
    echo '<html><body><h1>NACL Troubleshoot Web Server</h1><p>Port: 8080 / Environment: broken</p></body></html>' > /var/www/html/index.html
    nohup python3 -m http.server 8080 --directory /var/www/html >> /var/log/http-server.log 2>&1 &
  EOT
}

# -------------------------------------------------------
# Amazon Linux 2023 最新 AMI を動的取得
# -------------------------------------------------------
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -------------------------------------------------------
# VPC
# -------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-vpc"
  })
}

# -------------------------------------------------------
# パブリックサブネット
# -------------------------------------------------------
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-public-subnet"
  })
}

# -------------------------------------------------------
# インターネットゲートウェイ
# -------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-igw"
  })
}

# -------------------------------------------------------
# パブリックルートテーブル
# -------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-public-rtb"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# -------------------------------------------------------
# Network ACL (BROKEN)
# 問題: アウトバウンドでエフェメラルポート(1024-65535)を許可していない
# → レスポンスパケットがブロックされクライアントがタイムアウトする
# -------------------------------------------------------
resource "aws_network_acl" "main" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.public.id]

  ingress {
    rule_no    = 100
    action     = "allow"
    protocol   = "tcp"
    from_port  = 8080
    to_port    = 8080
    cidr_block = "0.0.0.0/0"
  }

  # ポート8080のみ許可 → エフェメラルポート(1024-65535)が抜けている
  egress {
    rule_no    = 100
    action     = "allow"
    protocol   = "tcp"
    from_port  = 8080
    to_port    = 8080
    cidr_block = "0.0.0.0/0"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-nacl"
  })
}

# -------------------------------------------------------
# セキュリティグループ（ステートフル：戻りトラフィックは自動許可）
# -------------------------------------------------------
resource "aws_security_group" "ec2" {
  name        = "${var.project}-${var.environment}-ec2-sg"
  description = "Allow port 8080 inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Web server port 8080"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-ec2-sg"
  })
}

# -------------------------------------------------------
# Launch Template
# -------------------------------------------------------
resource "aws_launch_template" "main" {
  name_prefix   = "${var.project}-${var.environment}-lt-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = var.instance_type

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2.id]
  }

  user_data = base64encode(local.user_data)

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = "${var.project}-${var.environment}-ec2"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-lt"
  })
}

# -------------------------------------------------------
# Target Group
# -------------------------------------------------------
resource "aws_lb_target_group" "main" {
  name     = "${var.project}-${var.environment}-tg"
  port     = 8080
  protocol = "TCP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-tg"
  })
}

# -------------------------------------------------------
# Network Load Balancer
# -------------------------------------------------------
resource "aws_lb" "main" {
  name               = "${var.project}-${var.environment}-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = [aws_subnet.public.id]

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-nlb"
  })
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 8080
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# -------------------------------------------------------
# Auto Scaling Group (min:1 max:1)
# -------------------------------------------------------
resource "aws_autoscaling_group" "main" {
  name                = "${var.project}-${var.environment}-asg"
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = [aws_subnet.public.id]
  target_group_arns   = [aws_lb_target_group.main.arn]
  health_check_type   = "ELB"

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  tag {
    key                 = "Project"
    value               = var.project
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  tag {
    key                 = "ManagedBy"
    value               = "Terraform"
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-${var.environment}-ec2"
    propagate_at_launch = true
  }
}
