# 03_nacl-troubleshoot / broken

Network ACL のトラブルシューティング演習環境（問題あり版）。  
SOA-C03 試験で頻出の「NACLのエフェメラルポート不足」障害を再現する。

---

## 1. SOA-C03 出題パターン

試験では次のようなシナリオが出題される。

> VPC 内の EC2 インスタンスへの接続がタイムアウトする。  
> セキュリティグループは正しく設定されているのに、なぜ通信できないか？

**正解の切り口：Network ACL のアウトバウンドルールにエフェメラルポートが抜けている。**

試験のポイント：
- セキュリティグループ（SG）はステートフル → 問題なし
- Network ACL（NACL）はステートレス → エフェメラルポートの許可が必要
- VPC Flow Logs で `REJECT` を確認してから NACL を疑う流れが問われる

---

## 2. ステートフル（SG）とステートレス（NACL）の違い

| 特性 | セキュリティグループ（SG） | Network ACL（NACL） |
|------|--------------------------|---------------------|
| 適用レベル | インスタンス単位 | サブネット単位 |
| ステート管理 | **ステートフル** | **ステートレス** |
| 戻りトラフィック | 自動的に許可 | 明示的に許可が必要 |
| ルール評価 | すべてのルールを評価 | 番号順（最初にマッチで終了） |
| デフォルト | インバウンド全拒否 / アウトバウンド全許可 | すべて許可 |

### ステートフルとは

SG はコネクションを追跡する。クライアントからポート 8080 へのリクエストを許可した場合、その応答パケット（戻りトラフィック）は **自動的に** 通過する。アウトバウンドルールに何も書かなくてよい。

### ステートレスとは

NACL はパケットを個別に判断する。コネクション状態を追跡しない。  
クライアントが `1.2.3.4:54321 → EC2:8080` で接続した場合：
- **インバウンド**：`dst port 8080` → NACL インバウンドルールで判断
- **アウトバウンド**（応答）：`src port 8080, dst port 54321` → NACL アウトバウンドルールで判断

応答パケットの宛先ポートは `54321`（エフェメラルポート）なので、アウトバウンドルールに `1024-65535` の許可がないと **REJECT** される。

---

## 3. エフェメラルポートとは

TCP/UDP 通信でクライアント側が一時的に使うポート番号。

- **範囲**: 1024 ～ 65535（Linux カーネルのデフォルト）
- **用途**: クライアントが接続要求を送る際にOSが自動割り当て
- **特徴**: 通信終了後に解放され、次の通信で別の番号が使われる

```
クライアント (54321) ──→ サーバー (8080)   ← インバウンドポート: 8080
クライアント (54321) ←── サーバー (8080)   ← アウトバウンドの宛先ポート: 54321
```

NACL のアウトバウンドルールが `8080` しか許可していない場合、応答パケットの宛先 `54321` はブロックされる。これが本環境の障害原因。

---

## 4. VPC Flow Logs の見方

### ログフォーマット

```
version account-id interface-id srcaddr dstaddr srcport dstport protocol packets bytes start end action log-status
```

### ACCEPT と REJECT の読み方

**正常（fixed 環境）：**
```
2 123456789012 eni-abc123 1.2.3.4 10.0.1.10 54321 8080 6 5 300 1716000000 1716000060 ACCEPT OK
2 123456789012 eni-abc123 10.0.1.10 1.2.3.4 8080 54321 6 5 1500 1716000000 1716000060 ACCEPT OK
```
- 1行目: クライアント → EC2 (dst port: 8080) → `ACCEPT`
- 2行目: EC2 → クライアント (dst port: 54321) → `ACCEPT`

**障害（broken 環境）：**
```
2 123456789012 eni-abc123 1.2.3.4 10.0.1.10 54321 8080 6 5 300 1716000000 1716000060 ACCEPT OK
2 123456789012 eni-abc123 10.0.1.10 1.2.3.4 8080 54321 6 5 1500 1716000000 1716000060 REJECT OK
```
- 1行目: クライアント → EC2 (dst port: 8080) → `ACCEPT`（受信はできている）
- 2行目: EC2 → クライアント (dst port: 54321) → **`REJECT`**（応答がブロックされている）

### CloudWatch Logs Insights クエリ例

```
fields @timestamp, srcAddr, dstAddr, srcPort, dstPort, action
| filter action = "REJECT"
| sort @timestamp desc
| limit 50
```

---

## 5. broken → fixed の変更点

`broken/main.tf` の NACL アウトバウンドルール：

```hcl
# NACL アウトバウンド（broken）
egress {
  rule_no    = 100
  action     = "allow"
  protocol   = "tcp"
  from_port  = 8080
  to_port    = 8080
  cidr_block = "0.0.0.0/0"
}
# ← ルール200 が存在しない（エフェメラルポートの許可なし）
```

`fixed/main.tf` の NACL アウトバウンドルール：

```hcl
# NACL アウトバウンド（fixed）
egress {
  rule_no    = 100
  action     = "allow"
  protocol   = "tcp"
  from_port  = 8080
  to_port    = 8080
  cidr_block = "0.0.0.0/0"
}
# ↓ ルール200 を追加（エフェメラルポートの許可）
egress {
  rule_no    = 200
  action     = "allow"
  protocol   = "tcp"
  from_port  = 1024
  to_port    = 65535
  cidr_block = "0.0.0.0/0"
}
```

---

## 6. Terraform 実行手順

### 前提条件

- AWS CLI が設定済み（`aws configure`）
- Terraform 1.6.0 以上インストール済み
- broken と fixed は**同時にデプロイしない**（リソース名が競合する可能性がある）

### デプロイ

```bash
cd environments/03_nacl-troubleshoot/broken

terraform init
terraform fmt       # フォーマット確認
terraform validate  # 構文チェック
terraform plan      # 変更内容の確認
terraform apply     # デプロイ実行（yes で確認）
```

### アウトプット確認

```bash
terraform output nlb_dns_name
terraform output cloudwatch_log_group
```

### 削除

```bash
terraform destroy   # リソース削除（yes で確認）
```

---

## 7. 検証手順

### Step 1: curl でアクセスを試みる（タイムアウトを確認）

```bash
NLB_DNS=$(terraform output -raw nlb_dns_name)

# タイムアウトになることを確認（--max-time 15秒）
curl --max-time 15 http://${NLB_DNS}:8080
```

**期待される結果（broken）：** `curl: (28) Operation timed out`  
NLB のヘルスチェックは同一サブネット内で完結するため「正常」と表示されるが、外部からはレスポンスが返らない。

### Step 2: VPC Flow Logs でREJECTを確認

1. AWS マネジメントコンソール → **CloudWatch** → **ロググループ**
2. `/aws/vpc/nacl-troubleshoot` を選択
3. 最新のログストリームを選択
4. **Logs Insights** で以下のクエリを実行：

```
fields @timestamp, srcAddr, dstAddr, srcPort, dstPort, action
| filter action = "REJECT"
| sort @timestamp desc
| limit 20
```

**確認ポイント：**
- `dstPort` が 1024〜65535 の範囲でREJECTされているログを探す
- これが「エフェメラルポートへの応答がブロックされている」証拠

### Step 3: fixed 環境でアクセスを確認

```bash
# broken を削除してから fixed をデプロイ
terraform destroy

cd ../fixed
terraform init && terraform apply

NLB_DNS=$(terraform output -raw nlb_dns_name)

# 少し待ってから（EC2とNLBの起動に2〜3分かかる）
curl http://${NLB_DNS}:8080
```

**期待される結果（fixed）：** `<html><body><h1>NACL Troubleshoot Web Server</h1>...`

### Step 4: Flow Logs で ACCEPT を確認（fixed）

fixed 環境で同じ Logs Insights クエリを実行し、インバウンド・アウトバウンド両方が `ACCEPT` になっていることを確認する。

---

## アーキテクチャ図

```
インターネット
    |
[クライアント]  ← curl http://NLB:8080
    |
[Internet Gateway]
    |
[パブリックサブネット 10.0.1.0/24]
  ┌─────────────────────────────────────────────┐
  │  [NACL] ← ここでエフェメラルポートをチェック  │
  │                                              │
  │  [NLB] → [EC2:8080 (ASG)]                   │
  └─────────────────────────────────────────────┘
    |
[VPC Flow Logs] → [CloudWatch Logs]
```

---

## 注意事項

- この環境は**学習目的**のため NACL で全拒否しており、EC2 から外部への通信も制限される
- broken と fixed は同時にデプロイしないこと（IAM ロール名・NLB 名が変わるが CloudWatch Log Group 名が重複する）
- NLB は Free Tier 対象外のため、**検証後は必ず `terraform destroy` で削除**すること

---

## 実際の検証で発見した追加ポイント

### 1. NLB Client IP Preservation の影響

- NLB はデフォルトで **Client IP Preservation がオン**
- オンの場合、クライアントの実 IP がそのまま EC2 に届く
- 「EC2 直接アクセスは成功するが NLB 経由でタイムアウトする」場合はこの設定を確認すること
- 確認場所：**ターゲットグループ → 属性 → クライアント IP アドレスの保持**

### 2. VPC Flow Logs のログストリームが 2 つある理由

Flow Logs を確認するとログストリームが複数存在する。

| ログストリーム | 対象 ENI | 内容 |
|--------------|----------|------|
| `eni-xxxxxxxx` (EC2) | EC2 インスタンスの ENI | インスタンスへ届いた通信のログ |
| `eni-yyyyyyyy` (NLB) | NLB ノードの ENI | ロードバランサー自体の通信ログ |

**REJECT ログは EC2 側の ENI で確認する。** NLB 側の ENI ではなく、EC2 の ENI のログストリームを選ぶこと。

### 3. 設定変更の反映時間

| 設定 | 反映時間 |
|------|----------|
| Network ACL ルール | **即時反映** |
| ターゲットグループ属性（Client IP Preservation 等） | 1〜2 分程度かかる場合あり |

変更後すぐ curl でテストして「まだタイムアウトする」と焦らないこと。

### 4. トラブルシューティング手順

```
Step 1: EC2 に直接 curl（EC2 のパブリック IP を使用）
        ↓ 成功 → EC2 自体は正常。NLB または NACL の問題
        ↓ 失敗 → SG またはアプリケーションの問題

Step 2: NLB 経由で curl（NLB の DNS 名を使用）
        ↓ タイムアウト → 以下を確認
           ① NACL アウトバウンドにエフェメラルポート (1024-65535) があるか
           ② Client IP Preservation が有効な場合、ループバック通信になっていないか

Step 3: VPC Flow Logs で REJECT を確認
        → EC2 の ENI のログストリームを選び、dstPort が 1024-65535 の REJECT を探す
```
