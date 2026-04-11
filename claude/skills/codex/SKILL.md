---
name: codex
description: Claude実装後のセカンドレビュー・多角的コード分析にCodex CLIを活用する
---

# Codex CLI スキル

**目的**: Claude の実装に対して OpenAI Codex によるセカンドオピニオンを取得する。
同じ問題を別のAIが独立して分析することで、見落とし・盲点・代替案を発見する。

## コマンド

`/codex <リクエスト内容>`

---

## Codexを使う場面 / 使わない場面

| 使う ✅ | 使わない ❌ |
|--------|-----------|
| Claude実装後の品質・セキュリティレビュー | ファイル編集・作成（Claudeが直接やる） |
| 網羅的なバグ・脆弱性の洗い出し | 単純な検索・読み込み |
| 大規模コードの依存関係・影響範囲調査 | 既知の明確な実装タスク |
| 「他に問題はないか？」の確認 | ユーザーが即時応答を期待している場面 |

---

## 実行手順

### 1. 前提チェック（毎回実行）

```bash
# CLI存在確認
which codex || { echo "[エラー] codexが見つかりません。インストール: npm install -g @openai/codex"; exit 0; }

# 認証確認（失敗時は自動でブラウザ認証を起動）
codex login status 2>&1 | grep -q "Logged in" || {
    echo "Codexの認証が必要です。ブラウザでログインしてください..."
    codex login --device-auth
}
```

### 2. Codex実行

**調査・レビュー・分析（デフォルト）:**
```bash
codex exec --full-auto --sandbox read-only --cd "$(pwd)" "<リクエスト>"
# timeout: 120,000ms
```

**コード変更の差分レビュー（git staged/unstaged）:**
```bash
codex review --base
# timeout: 120,000ms
```

**ファイル生成・変更を伴うタスク（ユーザー確認後）:**
```bash
codex exec --full-auto --sandbox none --cd "$(pwd)" "<リクエスト>"
# timeout: 300,000ms
```

### 3. 結果の活用

Codexの出力を受け取ったら:
- 指摘事項をClaudeが検証・精査する
- 重要な修正はClaudeが実装する（Codexはレビュアー、実装者はClaude）
- 矛盾する提案はユーザーに判断を仰ぐ

---

## エラーハンドリング

| 状況 | 対処 |
|------|------|
| 認証エラー（401 / Unauthorized / token expired） | `codex login --device-auth` を自動実行 → 完了後にリトライ |
| タイムアウト（120秒超） | 1回リトライ、再失敗は報告 |
| レート制限（429） | 30秒待機 → リトライ（最大2回） |
| CLI未インストール | `npm install -g @openai/codex` を案内して終了 |
| 連続失敗 / CLI不在 | Claude自身で同等の分析を実行して継続（ユーザーに通知） |

---

## 注意事項

- **モデル制限**: ChatGPTアカウントでは一部モデルが使用不可。`codex review --base` を使うと利用可能なモデルで自動実行される
- **機密情報**: APIキー・パスワードを含むリクエストは避ける
- **中断**: 長時間タスクは `Ctrl+C` で中断可能
