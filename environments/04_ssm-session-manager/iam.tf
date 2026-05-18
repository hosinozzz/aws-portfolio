# -------------------------------------------------------
# EC2用IAMロール（SSM Session Manager接続を許可）
# -------------------------------------------------------
resource "aws_iam_role" "ec2_ssm_role" {
  name = "${var.project}-${var.environment}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-ec2-ssm-role"
  })
}

# AmazonSSMManagedInstanceCore: SSM Agentの基本動作に必要なAWS管理ポリシー
resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# EC2インスタンスプロファイル（IAMロールをEC2に紐付けるラッパー）
resource "aws_iam_instance_profile" "ssm_profile" {
  name = "${var.project}-${var.environment}-ssm-instance-profile"
  role = aws_iam_role.ec2_ssm_role.name

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-ssm-instance-profile"
  })
}

# -------------------------------------------------------
# IAMポリシー：タグ条件付き Session Manager 接続制御
# SOA-C03ポイント: Conditionでタグ Env=production のEC2のみ許可
# -------------------------------------------------------
resource "aws_iam_policy" "production_ssm_access" {
  name        = "${var.project}-${var.environment}-production-ssm-access"
  description = "Allow SSM Session Manager access only to EC2 instances tagged Env=production"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSSMSessionToProductionOnly"
        Effect = "Allow"
        Action = [
          "ssm:StartSession"
        ]
        Resource = "arn:aws:ec2:${var.aws_region}:*:instance/*"
        Condition = {
          StringEquals = {
            "ssm:resourceTag/Env" = "production"
          }
        }
      },
      {
        Sid    = "AllowSSMSessionDocumentAccess"
        Effect = "Allow"
        Action = [
          "ssm:StartSession"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}::document/AWS-StartSSHSession"
      },
      {
        Sid    = "AllowSSMSessionTermination"
        Effect = "Allow"
        Action = [
          "ssm:TerminateSession",
          "ssm:ResumeSession"
        ]
        Resource = "arn:aws:ssm:*:*:session/$${aws:username}-*"
      },
      {
        Sid    = "AllowDescribeInstances"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ssm:DescribeSessions",
          "ssm:GetConnectionStatus",
          "ssm:DescribeInstanceProperties",
          "ssm:DescribeInstanceInformation"
        ]
        Resource = "*"
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-production-ssm-access"
  })
}

# -------------------------------------------------------
# IAMグループ：production環境へのアクセス権を持つグループ
# -------------------------------------------------------
resource "aws_iam_group" "production_access" {
  name = "production-access-group"
  path = "/"
}

resource "aws_iam_group_policy_attachment" "production_ssm_access" {
  group      = aws_iam_group.production_access.name
  policy_arn = aws_iam_policy.production_ssm_access.arn
}
