---
name: kb-harness
description: Claude Codeハーネス設計のナレッジベース。設計原則・hookテンプレ・トークン最適化を蓄積
user-invocable: true
---

# ハーネス設計ナレッジベース

## 設計原則

### トークン消費の公式
| 要素 | Claudeトークン | 使い方 |
|------|---------------|--------|
| command hook | **0** | 積極的に使う |
| prompt hook | 小 | 判定のみ |
| agent hook | **大** | 原則使わない |
| Codex exec | **0** | 実装は全て委譲 |
| CLAUDE.md | 毎ターン注入 | **200行以内** |
| rules/ | パス一致時のみ | pathsフロントマター必須 |
| memory/ | 先頭200行 | 簡潔に保つ |

### hook設計の3原則
1. **決定的**: Claudeの判断不要（ruff --fix, guard等）
2. **軽量**: timeout 30秒以内。重い処理は手動skill化
3. **非ブロッキング**: exit 0で通す（exit 2はPreToolUseガードのみ）

### exit codeの正しい使い方
- `exit 0`: 成功（hookを通す）
- `exit 2`: **ブロック**（PreToolUseでツール実行を阻止）
- `exit 1`: 非ブロッキングエラー（ログされるが続行。ブロック目的では使えない）

### 役割分担
- **Claude**: 設計・判断・レビュー（トークン消費を意識）
- **Codex**: 実装・テスト・修正（Claudeトークン0）
- **hook**: ローカル自動化（command typeのみ）
- **skill**: 手動トリガーの重い処理

### hook実行の注意
- 同一イベントの複数hookエントリは**並列実行**（順序保証なし）
- 1つのhooksエントリ内の配列は**順次実行**
- 順序依存がある場合は同じhooks配列にまとめる

## hookテンプレ

### PostToolUse: lint自動修正
```json
{"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "bash .claude/hooks/post-edit-guard.sh", "timeout": 30}]}
```

### PreToolUse: 安全装置（ifフィールドで対象限定）
```json
{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/guard.sh", "timeout": 5, "if": "Bash(collect_* || backfill_*)"}]}
```
`if`で対象コマンドを限定 → 不要なhook起動を削減。exit 2でブロック。

### Stop: 品質ゲート+自律改善（順次実行）
```json
{"matcher": "", "hooks": [
  {"type": "command", "command": "ruff check --quiet; exit 0", "timeout": 15},
  {"type": "command", "command": "bash .claude/hooks/record-failure.sh", "timeout": 10},
  {"type": "command", "command": "bash .claude/hooks/deviation-auto-promote.sh", "timeout": 10},
  {"type": "command", "command": "bash .claude/hooks/auto-consolidate-permissions.sh", "timeout": 10}
]}
```

### SessionStart: コンテキスト再注入
```json
{"matcher": "", "hooks": [{"type": "command", "command": "bash .claude/hooks/session-context.sh", "timeout": 15}]}
```
出力: `{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}`

## ディレクトリ構造テンプレ
```
.claude/
  settings.json         # hooks設定
  hooks/                # command hookスクリプト
    post-edit-guard.sh  # lint自動修正
    pre-scraper-guard.sh # 安全装置（exit 2でブロック）
    session-context.sh  # コンテキスト復旧
    record-failure.sh   # 失敗パターン自動記録
    deviation-auto-promote.sh  # ルール自動昇格
    auto-consolidate-permissions.sh  # 許可コマンド自動統合
  rules/                # パス別ルール（pathsフロントマター必須）
    backend/
    learned/            # deviation自動昇格先
  agents/               # name=英語小文字+ハイフン
  skills/               # プロジェクト固有スキル
```

## 失敗自動記録→自動ルール化（トークン0）

```
失敗発生 → Stop hook
  ↓
record-failure.sh
  transcript解析 → エラーパターン検出 → deviations.md追記
  ↓
deviation-auto-promote.sh
  count >= 3 → rules/learned/ にルール自動生成
  ↓
次回セッション
  rules/learned/ 自動読み込み → 同じ失敗を防止
```

## permissions自動統合（トークン0）

settings.local.jsonのpermissions.allowが30件超で自動汎用化:
- 完全パス(/Users/...)を削除
- コメント付き(# ...)を削除
- 同じプレフィクスを統合（poetry run python:* → poetry:*）
- 実績: 133件→20件に圧縮

## プロセス安全管理

process_manager.sh でPID+ラベル管理:
- pm_register/pm_unregister/pm_list/pm_cleanup
- 保護ラベル(backfill, pipeline, retrain)はpm_cleanupから除外
- pkillの巻き添え防止

## CLAUDE.md多層圧縮パターン

**移行判断基準**:
- 毎ターン参照が必要 → CLAUDE.mdに残す
- 時々参照する詳細 → kb-*に移行
- 上位階層と重複 → 削除して「上位を継承」の一行に
- 実績: 432行→166行（-62%）

## やってはいけないこと
- agent type hookを常時実行（トークン大量消費）
- CLAUDE.mdを200行超（毎ターン注入）
- rules/にpathsなし（全ファイルで注入）
- exit 1を「ブロック」目的で使う（exit 2が正解）
- hookからClaude API呼び出し（二重消費）
- hookでソースコード自動修正ループ（agent hookが必要→トークン消費大）

## 実績
- CLAUDE.md圧縮: 432→166行（毎ターン266行削減）
- agent hook削除: 毎Stop時のAPI call排除
- auto-codex-review削除: 毎Edit/WriteのCodex呼び出し排除
- permissions統合: 133→20件（Yes確認の大幅削減）

## 汎用テンプレート（新プロジェクト用）

### 使い方
新プロジェクト開始時にこの構成をコピーし、ドメイン固有部分だけ変更する。

### 基本構成（全プロジェクト共通）
```
.claude/
  settings.json           # 下記テンプレを使用
  hooks/
    post-edit-guard.sh    # PostToolUse: lint自動修正
    record-failure.sh     # Stop: 失敗パターン自動記録
    deviation-auto-promote.sh  # Stop: 3回以上で自動ルール化
    auto-consolidate-permissions.sh  # Stop: 許可コマンド自動統合
    session-context.sh    # SessionStart: コンテキスト再注入
  rules/
    learned/              # deviation自動昇格先（自動生成）
  agents/                 # ドメイン固有エージェント
```

### settings.jsonテンプレ
```json
{
  "hooks": {
    "PostToolUse": [{"matcher": "Edit|Write", "hooks": [
      {"type": "command", "command": "bash .claude/hooks/post-edit-guard.sh", "timeout": 30}
    ]}],
    "Stop": [{"matcher": "", "hooks": [
      {"type": "command", "command": "bash .claude/hooks/record-failure.sh", "timeout": 10},
      {"type": "command", "command": "bash .claude/hooks/deviation-auto-promote.sh", "timeout": 10},
      {"type": "command", "command": "bash .claude/hooks/auto-consolidate-permissions.sh", "timeout": 10}
    ]}],
    "SessionStart": [{"matcher": "", "hooks": [
      {"type": "command", "command": "bash .claude/hooks/session-context.sh", "timeout": 15}
    ]}]
  }
}
```

### ドメイン別追加パターン

#### Kaggle型（playground-s6e4で実証済み）
```
追加agents/: accuracy-improver, model-researcher, pipeline-builder
追加hooks/: submission-validator.sh（提出ファイル分布チェック）
追加memory/: strategy.md, cv_lb_gap.md, phase_results.md
特徴: エージェント多め、バリデーション重視
```

#### 運用型（keibaで実証済み）
```
追加hooks/: pre-scraper-guard.sh（安全装置）
追加rules/: backend/code-style.md, ml-development.md, scraping.md
追加agents/: code-reviewer, data-collector, ml-validator
追加scripts/: ループハーネス7つ、LaunchAgent、full_pipeline.sh
特徴: hook多め、自動化重視、ループハーネスで自律運用
```

#### 共通で有効なパターン
- deviations.md + learned_rules.md（失敗記録→自動ルール化）
- CLAUDE.md圧縮（詳細はkb-*に移行）
- permissions自動統合（30件超で汎用化）

## 公式ドキュメント
- [Hooks](https://code.claude.com/docs/en/hooks.md)
- [Skills](https://code.claude.com/docs/en/skills.md)
- [Memory](https://code.claude.com/docs/en/memory.md)
- [.claude directory](https://code.claude.com/docs/en/claude-directory.md)
- [Anthropic Claude Code](https://docs.anthropic.com/en/docs/claude-code)
