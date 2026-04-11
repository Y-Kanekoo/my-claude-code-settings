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

### 役割分担
- **Claude**: 設計・判断・レビュー（トークン消費を意識）
- **Codex**: 実装・テスト・修正（Claudeトークン0）
- **hook**: ローカル自動化（command typeのみ）
- **skill**: 手動トリガーの重い処理

## hookテンプレ

### PostToolUse: lint自動修正
```json
{"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "bash .claude/hooks/post-edit-guard.sh", "timeout": 30}]}
```

### PreToolUse: 安全装置
```json
{"matcher": "Bash", "hooks": [{"type": "command", "command": "bash .claude/hooks/guard.sh", "timeout": 5}]}
```
exit 2でブロック、exit 0で通過。

### Stop: 品質ゲート（ローカル）
```json
{"matcher": "", "hooks": [{"type": "command", "command": "cd backend && .venv/bin/python -m ruff check . --quiet; exit 0", "timeout": 15}]}
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
    guard.sh            # 安全装置（exit 2でブロック）
    session-context.sh  # コンテキスト復旧
  rules/                # パス別ルール
    backend/            # pathsフロントマター必須
    learned/            # deviation自動昇格
  agents/               # name=英語小文字+ハイフン
  skills/               # プロジェクト固有スキル
```

## やってはいけないこと
- agent type hookを常時実行（トークン大量消費）
- CLAUDE.mdを200行超（毎ターン注入）
- rules/にpathsなし（全ファイルで注入）
- hookでexit 1（何もブロックしない）
- hookからClaude API呼び出し（二重消費）
- hookでソースコード自動修正ループ（agent hookが必要→トークン消費大）

## 公式ドキュメント
- [Hooks](https://code.claude.com/docs/en/hooks.md)
- [Skills](https://code.claude.com/docs/en/skills.md)
- [Memory](https://code.claude.com/docs/en/memory.md)
- [.claude directory](https://code.claude.com/docs/en/claude-directory.md)
- [Anthropic Claude Code](https://docs.anthropic.com/en/docs/claude-code)
