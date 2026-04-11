# ハーネス設計テンプレート

## 設計方針: 「最小から足す」

> グローバル設定が厚いため、プロジェクトテンプレートは**補完のみ**。
> 重複を避け、プロジェクト固有の差分だけ記述する。

## ティア構成

| ティア | 対象 | 構成 |
|--------|------|------|
| **Tier 1** | 全プロジェクト（必須） | CLAUDE.md + settings.local.json |
| **Tier 2** | 標準プロジェクト | Tier 1 + PostToolUseフック |
| **Tier 3** | 大規模・長期プロジェクト | Tier 2 + commands/ + agents/ |

## 使い方

```bash
# 1. プロジェクトディレクトリ作成
mkdir -p ~/Projects/<project-name>
cd ~/Projects/<project-name>
git init

# 2. Tier 1（必須）をコピー
cp ~/.claude/templates/harness/CLAUDE.md.template ./CLAUDE.md
mkdir -p .claude
cp ~/.claude/templates/harness/settings.local.json.template .claude/settings.local.json

# 3. CLAUDE.md の TODO を埋める

# 4. 必要に応じて Tier 2/3 を追加
# Tier 2: PostToolUseフック
cp ~/.claude/templates/harness/post-validate.sh.template .claude/hooks/post-validate.sh
chmod +x .claude/hooks/post-validate.sh

# Tier 3: commands/ と agents/ のスケルトン
mkdir -p .claude/commands .claude/agents
cp ~/.claude/templates/harness/command.md.template .claude/commands/<name>.md
cp ~/.claude/templates/harness/agent.md.template .claude/agents/<name>.md
```

## ティア昇格の判断基準

- **Tier 1 → 2**: プロジェクト固有のバリデーションが必要になった時
- **Tier 2 → 3**: 同じ操作を2回以上手動で指示した時（コマンド化）、同じエージェント指示を2回再利用した時（エージェント化）

## グローバルで提供済み（プロジェクトで再定義不要）

- 言語設定（日本語回答、コード内コメント日本語）
- Git運用（コミットガイド、ブランチ戦略）
- 並列化ルール（Agent tool活用）
- セキュリティ制約（any禁止、.envコミット禁止）
- 自動改善ループ（検出→記録→学習→防止）
- PreToolUseガード（危険コマンドブロック）
- PostToolUseレビュー（Codex自動レビュー）
- Stopフック（自動コミット、改善分析、通知）
