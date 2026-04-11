# My Claude Code Settings

Claude Code（Anthropic の AI コーディングエージェント）の個人設定ファイル集です。

## 特徴

- **133パターンの権限設定** — 安全な自動承認（defaultMode: auto）運用
- **4層フックシステム** — PreToolUse / PostToolUse / Stop で品質ゲート
- **9カテゴリのナレッジベース** — `skills/kb-*` に知見を蓄積
- **出力ズレの自動学習ループ** — 検出 → 記録 → 学習 → 防止
- **Codex CLI連携** — 自動コミット + セカンドレビュー
- **カスタムステータスライン** — CPU/メモリ/GPU/git status 表示
- **ハーネステンプレート** — 新規プロジェクトの Tier 1/2/3 段階設計
- **双方向同期** — `/sync-settings` で GitHub と同期

## 構成

```
my-claude-code-settings/
├── claude/                          # ~/.claude/ のミラー
│   ├── CLAUDE.md                    # グローバル指示（言語・Git・並列化ルール）
│   ├── settings.json                # 権限 + Hook + ステータスライン
│   ├── settings.local.json          # MCP 追加権限
│   ├── commands/                    # カスタムコマンド
│   │   └── codex-model.md           #   Codex モデル確認
│   ├── config/
│   │   └── auto-commit.conf         #   自動コミット設定
│   ├── scripts/                     # フックスクリプト (13本)
│   │   ├── auto-commit-on-stop.sh   #   Stop: 自動コミット + Codex レビュー
│   │   ├── analyze-deviations.sh    #   Stop: 出力ズレ分析・学習
│   │   ├── guard-dangerous-bash.sh  #   PreToolUse: 危険コマンドガード
│   │   ├── stylish-statusline.sh    #   カスタムステータスライン
│   │   ├── auto-commit-milestone.sh #   PostToolUse: マイルストーン自動コミット
│   │   ├── post-validate-kaggle.sh  #   PostToolUse: 提出ファイルバリデーション
│   │   ├── auto-codex-review.sh     #   Codex 自動レビュー
│   │   ├── validate-dotfiles.sh     #   公開前の個人情報チェック
│   │   ├── setup-obsidian.sh        #   Obsidian 連携セットアップ
│   │   ├── validate-obsidian-links.sh
│   │   ├── gh-cache-updater.sh      #   GitHub 情報キャッシュ
│   │   ├── suggest-permission.sh    #   権限提案
│   │   └── lib/
│   │       ├── deviation_recorder.sh
│   │       └── timeout_compat.sh
│   ├── skills/                      # カスタムスキル (16個)
│   │   ├── kb-kaggle/               #   Kaggle コンペナレッジベース
│   │   ├── kb-patterns/             #   設計パターン集
│   │   ├── kb-git/                  #   Git/CI/CD
│   │   ├── kb-troubleshooting/      #   トラブルシューティング
│   │   ├── kb-harness/              #   ハーネス設計
│   │   ├── kb-database/             #   DB/SQL/ORM
│   │   ├── kb-frontend/             #   React/Vue/Tailwind
│   │   ├── kb-python/               #   Python
│   │   ├── kb-docker/               #   Docker/K8s
│   │   ├── review/                  #   コード品質分析
│   │   ├── review-fix/              #   コード修正レビュー
│   │   ├── review-harness/          #   ハーネス設計評価
│   │   ├── sync-knowledge/          #   ナレッジ同期
│   │   ├── sync-settings/           #   設定リポジトリ同期
│   │   ├── codex/                   #   Codex セカンドレビュー
│   │   └── marp-slide/              #   Marp スライド作成
│   └── templates/harness/           # 新規PJ用テンプレート
│       ├── README.md                #   ハーネス設計ガイド
│       ├── CLAUDE.md.template
│       ├── settings.local.json.template
│       ├── agent.md.template
│       ├── command.md.template
│       ├── post-validate.sh.template
│       └── deviation-config.json.template
├── examples/                        # プロジェクト階層の CLAUDE.md 設計例
│   ├── Projects-CLAUDE.md           #   ~/Projects/ 共通設定
│   └── kaggle-CLAUDE.md             #   Kaggle コンペ共通設定
└── mcp/                             # MCP サーバー設定例
    ├── global-mcp.json              #   context7 (ドキュメント検索)
    └── projects-mcp.json            #   playwright (ブラウザ自動化)
```

## 使い方

### 全設定をコピー

```bash
# バックアップ
cp -r ~/.claude ~/.claude.bak

# コピー
cp claude/CLAUDE.md ~/.claude/
cp claude/settings.json ~/.claude/
cp -r claude/scripts ~/.claude/
cp -r claude/skills ~/.claude/
cp -r claude/templates ~/.claude/
```

### 部分的に使う

必要なファイルだけコピーしてください:

```bash
# フックスクリプトだけ
cp -r claude/scripts ~/.claude/

# ナレッジベースだけ
cp -r claude/skills/kb-* ~/.claude/skills/

# テンプレートだけ
cp -r claude/templates ~/.claude/
```

### 設定同期（双方向）

```
/sync-settings        # 差分確認
/sync-settings push   # ~/.claude/ → リポジトリ
/sync-settings pull   # リポジトリ → ~/.claude/
```

## 主要コンポーネント解説

### フックシステム

```
ライフサイクル:
  ユーザー入力 → PreToolUse → [ツール実行] → PostToolUse → ... → Stop

PreToolUse (実行前ガード):
  └── guard-dangerous-bash.sh — rm -rf, sudo 等をブロック

PostToolUse (実行後バリデーション):
  ├── auto-commit-milestone.sh — テスト合格時に自動コミット
  └── post-validate-kaggle.sh — 提出ファイル・OOF の品質チェック

Stop (応答完了時):
  ├── auto-commit-on-stop.sh — 変更の自動コミット + Codex レビュー
  └── analyze-deviations.sh — 出力ズレを検出・記録・学習ルール昇格
```

### ナレッジベース（kb-*）

Claude Code の会話を跨いで知見を蓄積する仕組みです。`/kb-kaggle` のようにスラッシュコマンドで呼び出し、関連する知見を参照できます。

| スキル | エントリ数 | 内容 |
|--------|----------|------|
| kb-kaggle | 19 | GBDT比較、アンサンブル戦略、CV-LB天井現象 |
| kb-patterns | 12 | ハーネス設計、エスカレーションラダー、品質ゲート |
| kb-git | 11 | ブランチ戦略、サブエージェント並列作業、Actions |
| kb-troubleshooting | 15 | 環境構築、依存関係、各種エラー対応 |

### ハーネステンプレート

新規プロジェクト開始時に段階的に設定を追加する仕組みです:

| Tier | 構成 | 追加タイミング |
|------|------|--------------|
| Tier 1（必須） | CLAUDE.md + settings.local.json | 全プロジェクト |
| Tier 2（標準） | + PostToolUse フック | バリデーションが必要になった時 |
| Tier 3（フル） | + commands/ + agents/ | 同じ操作を2回以上手動指示した時 |

### 出力ズレ学習ループ

Claude の出力が期待と異なった場合に自動で学習する仕組みです:

```
検出 (analyze-deviations.sh)
  → 記録 (memory/deviations.md)
  → パターン化 (3回以上再発)
  → ルール昇格 (memory/learned_rules.md)
  → 次回から自動防止
```

## カスタマイズのヒント

### CLAUDE.md

`claude/CLAUDE.md` は私の開発環境（M4 Pro Mac）に合わせた設定です。以下を自分の環境に変更してください:

- **開発環境テーブル**: 自分のマシンスペックに変更
- **言語設定**: 必要に応じて英語に変更
- **Git運用**: チーム開発なら trunk 以外のブランチ戦略に

### settings.json

- **permissions.allow**: 使うコマンドに合わせて調整
- **permissions.deny**: セキュリティ要件に合わせて追加
- **hooks**: 不要なフックは削除可能

### スクリプト

- `auto-commit-milestone.sh` / `post-validate-kaggle.sh` の `PROJECT_DIR` を自分のプロジェクトパスに変更
- macOS 前提のスクリプトあり（`osascript` 通知等）。Linux では代替が必要

## 前提環境

- macOS（一部スクリプトが macOS 依存）
- Claude Code CLI
- [Codex CLI](https://github.com/openai/codex)（自動レビュー機能で使用、なくても動作）
- Git, Python（uv）

## ライセンス

MIT License - 自由に使用・改変してください。
