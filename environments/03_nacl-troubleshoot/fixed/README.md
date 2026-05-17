# 03_nacl-troubleshoot / fixed

Network ACL のトラブルシューティング演習環境（修正済み版）。  
`broken` 環境との差分を確認して、NACL エフェメラルポート問題の解決方法を理解する。

> 詳細な解説は `../broken/README.md` を参照。

---

## 修正内容

### 問題の原因

NACL はステートレスなため、リクエストに対する**応答パケット**も明示的に許可する必要がある。  
クライアントのエフェメラルポート（1024-65535）宛のアウトバウンドルールが抜けていると、レスポンスがブロックされてタイムアウトになる。

### 変更箇所（`fixed/main.tf`）

```hcl
resource "aws_network_acl" "main" {
  # ... （インバウンドルールは broken と同じ）

  egress {
    rule_no    = 100
    action     = "allow"
    protocol   = "tcp"
    from_port  = 8080
    to_port    = 8080
    cidr_block = "0.0.0.0/0"
  }

  # ← broken にはこのブロックが存在しなかった
  egress {
    rule_no    = 200
    action     = "allow"
    protocol   = "tcp"
    from_port  = 1024    # エフェメラルポート開始
    to_port    = 65535   # エフェメラルポート終了
    cidr_block = "0.0.0.0/0"
  }
}
```

---

## Terraform 実行手順

### 前提条件

- `broken` 環境を先に `terraform destroy` で削除してからデプロイすること
- AWS CLI が設定済み（`aws configure`）

### デプロイ

```bash
cd environments/03_nacl-troubleshoot/fixed

terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

### アウトプット確認

```bash
terraform output nlb_dns_name
terraform output cloudwatch_log_group
```

### 削除

```bash
terraform destroy
```

---

## 検証手順

### EC2 と NLB の起動を待つ（約 3〜5 分）

```bash
NLB_DNS=$(terraform output -raw nlb_dns_name)

# NLB が準備できるまでポーリング
until curl --silent --max-time 5 http://${NLB_DNS}:8080 > /dev/null 2>&1; do
  echo "Waiting for NLB to be ready..."
  sleep 30
done

echo "NLB is ready!"
```

### curl でアクセス確認

```bash
curl http://${NLB_DNS}:8080
```

**期待される結果：**
```html
<html><body><h1>NACL Troubleshoot Web Server</h1><p>Port: 8080 / Environment: fixed</p></body></html>
```

### VPC Flow Logs で ACCEPT を確認

1. AWS コンソール → CloudWatch → ロググループ → `/aws/vpc/nacl-troubleshoot`
2. Logs Insights で以下を実行：

```
fields @timestamp, srcAddr, dstAddr, srcPort, dstPort, action
| filter dstPort > 1024 and dstPort < 65535
| sort @timestamp desc
| limit 20
```

**確認ポイント：** エフェメラルポート宛のパケットが `ACCEPT` になっていること（broken では `REJECT`）

### broken との比較

| 項目 | broken | fixed |
|------|--------|-------|
| NLB ヘルスチェック | 正常（同一サブネット内） | 正常 |
| curl の結果 | タイムアウト | HTMLレスポンス返却 |
| Flow Logs (dst port 1024-65535) | REJECT | ACCEPT |
| NACL アウトバウンド ルール200 | なし | あり（1024-65535） |

---

## セキュリティグループとNACLの比較まとめ

```
[SG: ステートフル]
  インバウンド: 8080 ALLOW → 自動的に戻りトラフィックも許可
  アウトバウンド: ALL ALLOW（または何もなくても戻り通信はOK）

[NACL: ステートレス]
  インバウンド:  rule100 ALLOW tcp 8080   ← リクエスト受信
  アウトバウンド: rule100 ALLOW tcp 8080   ← これはEC2からの能動的送信用
                 rule200 ALLOW tcp 1024-65535  ← 応答パケット用（必須）
                 rule*   DENY ALL
```

---

## 注意事項

- NLB は Free Tier 対象外のため、検証後は必ず `terraform destroy` で削除すること
- `broken` 環境と同時にデプロイすると CloudWatch Log Group 名が競合する
