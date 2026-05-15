# CLAUDE.md

## プロジェクト概要
AWS Free Tier の範囲内で Terraform を使って構築するインフラポートフォリオ。
設計・構築現場に対応するための実務ポートフォリオが目的。

## 自身のバックグラウンド
- オンプレミスインフラ（RHEL、VMware、Oracle）の経験 約5年
- AWS実務経験はほぼなし（Security Hub確認レベル）
- Terraform 初心者 → 丁寧な説明が必要
- 目標：設計・構築現場で通用するポートフォリオの作成

## プロジェクト構成方針
- 各構成は environments/ 配下のフォルダで段階的に分離
- 再利用可能なコードは modules/ に分離
- 各フォルダに README.md 必須（日本語）
- Free Tier 範囲を厳守（t2.micro、750時間/月 等）

## コーディングルール
- terraform fmt を常に通すこと
- 変数は variables.tf に分離
- 機密情報（AWSキー等）はハードコーディング禁止
- 各リソースに必須タグ: Project, Environment, ManagedBy=Terraform