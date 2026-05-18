# -------------------------------------------------------
# S3バケット：SSMセッションログ保存用
# -------------------------------------------------------
resource "aws_s3_bucket" "ssm_logs" {
  bucket        = "${var.project}-${var.environment}-ssm-session-logs-${var.aws_account_id}"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-ssm-session-logs"
  })
}

resource "aws_s3_bucket_versioning" "ssm_logs" {
  bucket = aws_s3_bucket.ssm_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ssm_logs" {
  bucket = aws_s3_bucket.ssm_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# パブリックアクセスを完全ブロック
resource "aws_s3_bucket_public_access_block" "ssm_logs" {
  bucket = aws_s3_bucket.ssm_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -------------------------------------------------------
# SSM Document：セッションログをS3に保存する設定
# -------------------------------------------------------
resource "aws_ssm_document" "session_manager_preferences" {
  name            = "MySSMSessionPreferences-${var.environment}"
  document_type   = "Session"
  document_format = "JSON"

  content = jsonencode({
    schemaVersion = "1.0"
    description   = "SSM Session Manager preferences with S3 logging"
    sessionType   = "Standard_Stream"
    inputs = {
      s3BucketName                = aws_s3_bucket.ssm_logs.bucket
      s3KeyPrefix                 = "session-logs/"
      s3EncryptionEnabled         = true
      cloudWatchLogGroupName      = ""
      cloudWatchEncryptionEnabled = false
      idleSessionTimeout          = "20"
      runAsEnabled                = false
      runAsDefaultUser            = ""
    }
  })

  tags = merge(local.common_tags, {
    Name = "${var.project}-${var.environment}-ssm-session-preferences"
  })
}

# -------------------------------------------------------
# S3バケットポリシー：SSMセッションログ書き込みを許可
# -------------------------------------------------------
resource "aws_s3_bucket_policy" "ssm_logs" {
  bucket = aws_s3_bucket.ssm_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSSMSessionManagerWrite"
        Effect = "Allow"
        Principal = {
          Service = "ssm.amazonaws.com"
        }
        Action = [
          "s3:GetEncryptionConfiguration"
        ]
        Resource = aws_s3_bucket.ssm_logs.arn
      },
      {
        Sid    = "AllowEC2RoleWrite"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.ec2_ssm_role.arn
        }
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.ssm_logs.arn}/session-logs/*"
      }
    ]
  })
}
