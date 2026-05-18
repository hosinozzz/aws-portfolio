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
# プライベートサブネット（SSMはSSH不要なのでプライベートでOK）
# -------------------------------------------------------
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-private-subnet"
  })
}

# -------------------------------------------------------
# プライベートルートテーブル（インターネット不要）
# -------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-private-rtb"
  })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# -------------------------------------------------------
# パブリックサブネット（デバッグ用ジャンプサーバー配置）
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
# パブリック用ルートテーブル
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
# セキュリティグループ（VPCエンドポイント用：HTTPS 443のみ）
# -------------------------------------------------------
resource "aws_security_group" "vpc_endpoint" {
  name        = "${var.project}-${var.environment}-vpce-sg"
  description = "Allow HTTPS for SSM VPC Endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-vpce-sg"
  })
}

# -------------------------------------------------------
# セキュリティグループ（EC2用：アウトバウンドのみ）
# -------------------------------------------------------
resource "aws_security_group" "ec2" {
  name        = "${var.project}-${var.environment}-ec2-sg"
  description = "EC2 security group for SSM Session Manager"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "ICMP (ping) from public subnet"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.public_subnet_cidr]
  }

  ingress {
    description = "SSH from public subnet"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.public_subnet_cidr]
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
# VPCエンドポイント（SSM用3つ）
# SSMはインターネットを経由せずAWSサービスと通信するために必要
# -------------------------------------------------------
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-ssm-endpoint"
  })
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-ssmmessages-endpoint"
  })
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-ec2messages-endpoint"
  })
}

# EC2 VPCエンドポイント（Interface型）
# SSM AgentがEC2 APIと通信するために必要
resource "aws_vpc_endpoint" "ec2" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-ec2-endpoint"
  })
}

# S3 VPCエンドポイント（Gateway型・無料）
# SSM AgentがプライベートサブネットからS3にアクセスするために必要
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-s3-endpoint"
  })
}

# -------------------------------------------------------
# EC2 Instance Connect Endpoint
# プライベートサブネット内のEC2にブラウザ/CLIからSSH接続するための踏み台代替
# -------------------------------------------------------
resource "aws_ec2_instance_connect_endpoint" "main" {
  subnet_id          = aws_subnet.private.id
  security_group_ids = [aws_security_group.vpc_endpoint.id]
  preserve_client_ip = false

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-eice"
  })
}

# -------------------------------------------------------
# EC2 インスタンス (1台目: Env=production)
# -------------------------------------------------------
resource "aws_instance" "production" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  user_data              = <<-EOF
    #!/bin/bash
    # ec2-userにパスワードを設定 (Serial Console用)
    echo "ec2-user:TempPass123!" | chpasswd
    passwd -u ec2-user
  EOF

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 8
    delete_on_termination = true

    tags = merge(local.common_tags, {
      Name = "${var.project}-production-root-volume"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-production-ec2"
    Env  = "production"
  })
}

# -------------------------------------------------------
# EC2 インスタンス (2台目: Env=staging)
# -------------------------------------------------------
resource "aws_instance" "staging" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  user_data              = <<-EOF
    #!/bin/bash
    # ec2-userにパスワードを設定 (Serial Console用)
    echo "ec2-user:TempPass123!" | chpasswd
    passwd -u ec2-user
  EOF

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 8
    delete_on_termination = true

    tags = merge(local.common_tags, {
      Name = "${var.project}-staging-root-volume"
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.project}-staging-ec2"
    Env  = "staging"
  })
}

# -------------------------------------------------------
# セキュリティグループ（ジャンプサーバー用：SSH 22番）
# -------------------------------------------------------
resource "aws_security_group" "jump" {
  name        = "${var.project}-${var.environment}-jump-sg"
  description = "Allow SSH inbound for debug jump server"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
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
    Name = "${var.project}-${var.environment}-jump-sg"
  })
}

# -------------------------------------------------------
# ジャンプサーバー EC2 (デバッグ用・パブリックサブネット)
# -------------------------------------------------------
resource "aws_instance" "jump" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.jump.id]
  key_name               = var.key_name

  root_block_device {
    volume_type           = "gp2"
    volume_size           = 8
    delete_on_termination = true

    tags = merge(local.common_tags, {
      Name = "${var.project}-debug-jump-root-volume"
    })
  }

  tags = merge(local.common_tags, {
    Name = "debug-jump-server"
  })
}
