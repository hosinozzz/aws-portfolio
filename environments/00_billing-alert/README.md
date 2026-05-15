# 00_billing-alert

## 概要

AWS Budgets を使って月次コストが設定額を超えた場合にメールアラートを送信する設定です。
他の環境を構築する前に**最初に適用する**ことを推奨します。

## アラートの動作

| タイミング | 条件 | 通知内容 |
|---|---|---|
| 早期警告 | 月次コストが予算の **80%**（= $0.80）を超えた時 | 消費超過の警告メール |
| 上限超過 | 月次コストが予算の **100%**（= $1.00）を超えた時 | 上限超過の警告メール |

## Free Tier 対応状況

- **AWS Budgets**: 1アカウントにつき **2予算まで無料**
- 本構成では予算を1つのみ作成するため無料枠内に収まる
- 3つ目以降の予算は $0.02/日 が課金されるため注意

## 前提条件

- Terraform >= 1.6.0
- AWS CLI が設定済み（`aws configure` 実行済み）
- AWS アカウントに請求情報へのアクセス権限があること

> **注意**: IAM ユーザーで実行する場合、ルートアカウントの「IAM ユーザーの請求情報アクセス」を有効にする必要があります。
> AWS コンソール → アカウント → 請求情報へのIAMユーザー/ロールアクセス → 有効化

## 使い方

### 1. terraform.tfvars の作成

```hcl
alert_email = "your-email@example.com"
```

> `alert_email` はデフォルト値なし・`sensitive = true` のため、必ず指定が必要です。
> `.gitignore` に `terraform.tfvars` を追加して Git にコミットしないこと。

### 2. 初期化・実行

```bash
cd environments/00_billing-alert
terraform init
terraform plan
terraform apply
```

### 3. メール確認

適用後、AWS から確認メールが届く場合があります。
メールボックスを確認してサブスクリプションを承認してください。

## 変数一覧

| 変数名 | デフォルト値 | 説明 |
|---|---|---|
| `aws_region` | `ap-northeast-1` | AWSリージョン |
| `project` | `aws-portfolio` | プロジェクト名（タグ用） |
| `environment` | `dev` | 環境名（タグ用） |
| `alert_email` | （必須） | アラート送信先メールアドレス |
| `budget_limit_usd` | `"1.0"` | 月次予算上限額（USD） |
| `warning_threshold_percentage` | `80` | 早期警告を送る消費率（%） |

## 出力値

| 出力名 | 説明 |
|---|---|
| `budget_id` | 作成された予算の ID |
| `budget_name` | 作成された予算の名前 |
| `budget_limit_usd` | 設定した月次予算上限額 |

## セキュリティ注意事項

- `alert_email` は `sensitive = true` に設定しているため `terraform plan` / `apply` の出力でマスクされます
- `terraform.tfvars` を作成した場合は `.gitignore` に必ず追加してください
