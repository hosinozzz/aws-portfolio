# 04_ssm-session-manager

## 概要

AWS Systems Manager Session Manager を使用したタグベースのEC2アクセス制御環境。  
**SOA-C03 問題20番**の出題内容を Terraform で実装したポートフォリオ構成。

---

## SOA-C03 問題20番 解説

### 問題の要点

**要件:** 特定のユーザーグループが `Env=production` タグを持つ EC2 インスタンスにのみ Session Manager で接続できるようにしたい。

**正解: A と E**

| 選択肢 | 内容 | 理由 |
|--------|------|------|
| **A** | IAMポリシーで `ssm:resourceTag/Env = production` の Condition を設定 | タグに基づいてリソースへのアクセスを制限できる。SOA-C03の核心ポイント |
| **B** | リソースベースポリシーをSSMドキュメントに設定 | セッション開始のリソース制御にはEC2のタグ条件が必要であり、SSMドキュメントのポリシーでは不十分 |
| **C** | SecurityGroupでSSHポートを制御 | Session Managerは443ポート経由でありSSHは不要。根本的に方向性が違う |
| **D** | SCPでアカウントレベル制御 | アカウント全体に影響し、特定グループへの制御としては粒度が粗い |
| **E** | EC2インスタンスにIAMロール（AmazonSSMManagedInstanceCore）をアタッチ | SSM AgentがAWSと通信するために必要なロール。これがないとSession Managerそのものが動作しない |

### なぜ A+E の組み合わせが正解か

```
[ユーザー] → IAMポリシー(Condition: Env=production) → [productionEC2のみ接続可]
                                                      → [stagingEC2は拒否]

[EC2] → IAMロール(AmazonSSMManagedInstanceCore) → SSM Agent が AWS と通信できる
```

- **A（IAMポリシーのCondition）**: ユーザー側の制御。誰がどのEC2に接続できるかを定義
- **E（EC2のIAMロール）**: EC2側の制御。SSM Agentが正常に動作するための前提条件

---

## タグベースアクセス制御の仕組み

### Condition要素の書き方（SOA-C03頻出）

```json
{
  "Effect": "Allow",
  "Action": "ssm:StartSession",
  "Resource": "arn:aws:ec2:ap-northeast-1:*:instance/*",
  "Condition": {
    "StringEquals": {
      "ssm:resourceTag/Env": "production"
    }
  }
}
```

- `ssm:resourceTag/<タグキー>` : SSMリソース（EC2）のタグ値で条件付け
- `StringEquals` : 完全一致。大文字小文字を区別する
- EC2の `Env=production` タグが一致する場合のみ `StartSession` を許可

### 動作確認シナリオ

| ユーザー | 対象EC2 | EC2のEnvタグ | 結果 |
|----------|---------|-------------|------|
| production-access-groupメンバー | production-ec2 | production | ✅ 接続可 |
| production-access-groupメンバー | staging-ec2 | staging | ❌ 拒否 |
| グループ外ユーザー | production-ec2 | production | ❌ 拒否（SSMポリシーなし） |

---

## SSM Session Manager のメリット

### SSH・踏み台サーバーが不要

| 従来構成 | SSM Session Manager |
|----------|---------------------|
| 踏み台サーバーの構築・運用コスト | 不要 |
| キーペア管理 | 不要 |
| セキュリティグループで22番ポート開放 | 不要（443のみ）|
| パブリックIPが必要 | プライベートサブネットでOK |

### ログ自動記録

Session Manager はセッションの全操作ログを自動で保存できる：

- **S3**: コマンド実行ログをテキストで保存（本環境で実装）
- **CloudWatch Logs**: リアルタイムでログ確認可能
- **CloudTrail**: セッション開始/終了のAPIコールを記録

### セキュリティ向上

- IAM認証によるアクセス制御（パスワード・鍵不要）
- タグベースで細かい権限設計が可能（本番/ステージングを分離）
- インバウンドポート開放不要でアタックサーフェスを削減

---

## 金融系現場での活用例

金融系・インフラ現場では特にSession Managerの利点が際立つ：

1. **鍵管理コストの削減**  
   サーバー数百台の SSH 鍵を管理する代わりに IAM ユーザー/ロールで一元管理

2. **監査証跡の確保**  
   全操作ログをS3に保存し、内部統制・コンプライアンス要件（金融庁ガイドライン等）に対応

3. **最小権限の徹底**  
   `Env=production` タグを使い、開発者は開発環境のみ・本番担当者のみが本番にアクセス可能

4. **ゼロトラスト実装の第一歩**  
   ネットワーク経路（SSH）ではなく ID（IAM）で制御 → ゼロトラストアーキテクチャへの移行

---

## アーキテクチャ図

```
[IAMユーザー]
     |
     | (IAMポリシー: Env=production のみ許可)
     v
[SSM Service (AWS managed)]
     |
     | (VPCエンドポイント経由)
     v
[プライベートサブネット 10.0.1.0/24]
     |
     +--- [EC2: production] Env=production ← 接続可
     |
     +--- [EC2: staging]    Env=staging    ← 拒否

※ インターネットGW・パブリックIP・SSHポート 一切不要
```

---

## 構成ファイル

| ファイル | 内容 |
|----------|------|
| `main.tf` | VPC・サブネット・EC2・VPCエンドポイント |
| `iam.tf` | EC2用IAMロール・タグ条件付きポリシー・IAMグループ |
| `ssm.tf` | セッションログ用S3バケット・SSMドキュメント |
| `variables.tf` | 変数定義 |
| `outputs.tf` | 接続コマンド等の出力 |
| `terraform.tfvars` | 変数値（要編集） |

---

## Terraform 実行手順

### 1. 事前準備

```bash
# terraform.tfvars の YOUR_ACCOUNT_ID を実際のAWSアカウントIDに変更
# 例:
aws_account_id = "123456789012"
```

### 2. 初期化

```bash
cd environments/04_ssm-session-manager
terraform init
```

### 3. 実行計画確認

```bash
terraform plan
```

### 4. 適用

```bash
terraform apply
```

### 5. Session Manager で接続確認

```bash
# production EC2 への接続（成功するはず）
aws ssm start-session --target <production_instance_id> --region ap-northeast-1

# staging EC2 への接続（production-access-group のユーザーは拒否されるはず）
aws ssm start-session --target <staging_instance_id> --region ap-northeast-1
```

> instance_id は `terraform output` で確認できます

### 6. 後片付け（Free Tier 超過防止）

```bash
terraform destroy
```

> **注意**: VPCエンドポイント（Interface型）は時間課金のため、使用後は必ず `terraform destroy` を実行すること。  
> 3つのエンドポイントで約 $0.01/時間 かかる。

---

## 注意事項

- VPCエンドポイント（Interface型）は **Free Tier対象外** のため、動作確認後は速やかに `terraform destroy` を実行してください
- `terraform.tfvars` の `aws_account_id` を自身のAWSアカウントIDに変更してから実行してください
- S3バケット名はグローバルで一意にする必要があるため、アカウントIDをサフィックスに使用しています

---

## 検証状況・未解決事項

### 構築済み ✅

- VPC + プライベートサブネット
- EC2 x2（production / staging タグ）
- VPCエンドポイント x4（ssm / ssmmessages / ec2messages / s3）
- IAM Role + タグ条件付き Policy
- S3セッションログバケット

### 未確認 ⚠️

- SSM Session Manager経由でのEC2接続
- マネージドノードへの登録

### 詰まっている箇所

全設定が正しいにもかかわらず、マネージドノードに登録されない（管理対象: False のまま）。

考えられる原因：

1. SSM Agentの初期化に想定以上の時間が必要
2. VPCエンドポイント経由のDNS解決の問題
3. 追加調査が必要

### 次のステップ

- EC2にSession Managerで接続し、SSM Agentのステータスを直接確認
- CloudWatch Logsでエージェントログを確認
