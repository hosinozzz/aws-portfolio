# 01_vpc-ec2-basic

## 概要

AWS Free Tier の範囲内で、最小構成の VPC と EC2 インスタンスを構築する Terraform コードです。

## 構成図

```
Internet
    |
[Internet Gateway]
    |
[VPC: 10.0.0.0/16]
    └── [Public Subnet: 10.0.1.0/24]
            └── [EC2: t2.micro / Amazon Linux 2023]
                    └── [Security Group: SSH(22) のみ許可]
```

## 作成されるリソース

| リソース | 設定値 |
|---|---|
| VPC | CIDR: 10.0.0.0/16 |
| パブリックサブネット | CIDR: 10.0.1.0/24 / AZ: ap-northeast-1a |
| インターネットゲートウェイ | VPC にアタッチ |
| ルートテーブル | デフォルトルート → IGW |
| セキュリティグループ | Inbound: SSH(22) / Outbound: ALL |
| EC2 インスタンス | t2.micro / Amazon Linux 2023 / EBS 8GB |

## Free Tier 対応状況

- **EC2**: t2.micro は月 750 時間まで無料
- **EBS**: gp2 / 8GB は月 30GB 無料枠内
- **データ転送**: 月 100GB アウトバウンドまで無料

## 前提条件

- Terraform >= 1.6.0
- AWS CLI が設定済み（`aws configure` 実行済み）
- EC2 に SSH 接続するためのキーペアが AWS に登録済み

## 使い方

### 1. キーペアの準備

AWS コンソール または CLI でキーペアを作成し、`.pem` ファイルを保存しておく。

```bash
aws ec2 create-key-pair \
  --key-name my-portfolio-key \
  --query 'KeyMaterial' \
  --output text > my-portfolio-key.pem

chmod 400 my-portfolio-key.pem
```

### 2. terraform.tfvars の作成（オプション）

`terraform.tfvars` ファイルを作成して変数を上書きできる（`.gitignore` 推奨）。

```hcl
key_name         = "my-portfolio-key"
allowed_ssh_cidr = "xxx.xxx.xxx.xxx/32"  # 自身のIPアドレスを指定
```

### 3. 初期化・実行

```bash
terraform init
terraform plan
terraform apply
```

### 4. SSH 接続確認

```bash
ssh -i my-portfolio-key.pem ec2-user@<instance_public_ip>
```

### 5. リソース削除（課金停止）

```bash
terraform destroy
```

## 変数一覧

| 変数名 | デフォルト値 | 説明 |
|---|---|---|
| `aws_region` | `ap-northeast-1` | AWSリージョン |
| `project` | `aws-portfolio` | プロジェクト名（タグ用） |
| `environment` | `dev` | 環境名（タグ用） |
| `vpc_cidr` | `10.0.0.0/16` | VPC の CIDR ブロック |
| `public_subnet_cidr` | `10.0.1.0/24` | パブリックサブネットの CIDR |
| `availability_zone` | `ap-northeast-1a` | アベイラビリティゾーン |
| `instance_type` | `t2.micro` | EC2 インスタンスタイプ |
| `key_name` | （必須） | SSH キーペア名 |
| `allowed_ssh_cidr` | `0.0.0.0/0` | SSH 許可 CIDR（本番では絞ること） |

## セキュリティ注意事項

- `allowed_ssh_cidr` のデフォルトは `0.0.0.0/0`（全開放）のため、**本番・長期運用では必ず自身の IP に絞ること**
- キーペアの `.pem` ファイルは Git にコミットしないこと
- `terraform.tfvars` に機密情報を書いた場合は `.gitignore` に追加すること

## 出力値

| 出力名 | 説明 |
|---|---|
| `vpc_id` | VPC の ID |
| `public_subnet_id` | パブリックサブネットの ID |
| `internet_gateway_id` | IGW の ID |
| `security_group_id` | セキュリティグループの ID |
| `instance_id` | EC2 インスタンスの ID |
| `instance_public_ip` | EC2 のパブリック IP |
| `instance_public_dns` | EC2 のパブリック DNS 名 |
