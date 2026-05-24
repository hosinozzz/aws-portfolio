# 05_cross-region-ha

## 概要

金融系システムを想定したクロスリージョン高可用性アーキテクチャ。  
東京（ap-northeast-1）と大阪（ap-northeast-3）の2リージョン構成で、  
障害発生時も自動フェイルオーバーによりサービスを継続する。

---

## アーキテクチャ図

```
Internet
    ↓
Route53 (Health Check + Failover)
            ↓                    ↓
東京 ALB                        大阪 ALB
(Primary)                   (Secondary)
    ↓                            ↓
+--東京 VPC (10.0.0.0/16)----+  +--大阪 VPC (10.1.0.0/16)----+
|                            |  |                            |
| Public  10.0.1.0/24 (AZ-a) |  | Public  10.1.1.0/24 (AZ-a) |
| Public  10.0.2.0/24 (AZ-c) |  | Public  10.1.2.0/24 (AZ-c) |
|                            |  |                            |
| Private 10.0.3.0/24 (AZ-a) |  | Private 10.1.3.0/24 (AZ-a) |
| Private 10.0.4.0/24 (AZ-c) |  | Private 10.1.4.0/24 (AZ-c) |
|                            |  |                            |
| DB      10.0.5.0/24 (AZ-a) |  | DB      10.1.5.0/24 (AZ-a) |
| DB      10.0.6.0/24 (AZ-c) |  | DB      10.1.6.0/24 (AZ-c) |
|                            |  |                            |
| Aurora Primary (Write)     |◄─►| Aurora Secondary (Failover)|
+-----------------------------+  +-----------------------------+
              ↑                              ↑
              └────────── VPC Peering ───────┘
```

---

## 構成リソース

### ネットワーク
| リソース | 東京 | 大阪 |
|---------|------|------|
| VPC | 10.0.0.0/16 | 10.1.0.0/16 |
| Public Subnet | x2 (AZ-a/c) | x2 (AZ-a/c) |
| Private Subnet | x2 (AZ-a/c) | x2 (AZ-a/c) |
| DB Subnet | x2 (AZ-a/c) | x2 (AZ-a/c) |
| IGW | ✅ | ✅ |
| NAT Gateway | x2 | x2 |
| VPC Peering | 東京↔大阪 | |

### ルートテーブル
| RT名 | 対象サブネット | ルート |
|------|-------------|--------|
| Public RT | Public Subnet | 0.0.0.0/0 → IGW |
| | | 10.1.0.0/16 → VPC Peering |
| Private RT | Private Subnet | 0.0.0.0/0 → NAT GW |
| | | 10.1.0.0/16 → VPC Peering |
| DB RT | DB Subnet | 10.1.0.0/16 → VPC Peering |

### データベース
| リソース | 内容 |
|---------|------|
| Aurora Global Database | MySQL 8.0 |
| Primary | 東京 (書き込み) |
| Secondary | 大阪 (読み取り / フェイルオーバー) |
| フェイルオーバー時間 | 約1分以内 |

### アプリケーション
| リソース | 内容 |
|---------|------|
| Lambda | 残高照会API |
| API Gateway | REST API |
| ALB | ヘルスチェック付き |
| Route53 | Failoverルーティング |

---

## 金融系要件との対応

| 要件 | 対応内容 | 実装 |
|------|---------|------|
| 高可用性 | Multi-AZ + クロスリージョン | Aurora Global DB |
| RTO | 目標: 60秒以内 | Route53 Failover |
| RPO | 目標: 1秒以内 | Aurora Global DB レプリケーション |
| データ保護 | 暗号化 + バックアップ | Aurora自動バックアップ |
| ネットワーク分離 | 3層サブネット構成 | Public/Private/DB |
| 通信制御 | Security Group多層制御 | ALB/App/DB用SG |

---

## フェイルオーバー検証手順

### 1. 正常時の確認
```bash
# 東京エンドポイントに連続リクエスト
while true; do
  curl -s https://api.example.com/health
  sleep 1
done
```

### 2. 障害シミュレーション
```bash
# 東京Lambdaを意図的にエラー状態に
# → Route53がヘルスチェック失敗を検知
# → 大阪エンドポイントへ自動切り替え
```

### 3. 確認ポイント
- [ ] Route53 ヘルスチェック失敗検知
- [ ] 大阪リージョンへの自動切り替え
- [ ] 切り替え時間の計測（RTO確認）
- [ ] Aurora Globalのフェイルオーバー確認

---

## 構築手順

```bash
# 1. 東京リージョン
cd tokyo/
terraform init
terraform apply

# 2. 大阪リージョン  
cd osaka/
terraform init
terraform apply

# 3. VPC Peering (東京側で実行)
cd peering/
terraform init
terraform apply
```

---

## 学習ポイント

- クロスリージョンVPC Peeringのルートテーブル設定
- Aurora Global Databaseのフェイルオーバー動作
- Route53 Health CheckによるDNSフェイルオーバー
- 金融系3層ネットワーク設計（Public/Private/DB）

---

## 注意事項

⚠️ **課金対象リソース**
- NAT Gateway: 約$0.062/時間 × 4 = 約$0.25/時間
- Aurora: 約$0.073/時間
- VPC Peering データ転送: $0.01/GB

検証後は必ず `terraform destroy` を実行してください。

---

*本構成は金融系システムの要件を学習目的で再現したものです。*