# プロジェクト共通設定

> グローバル設定（~/.claude/CLAUDE.md）を継承。以下はプロジェクト共通の追加・上書き設定のみ。

## トークン最適化（必須）
- **Claude**: 設計・判断・レビューのみ。ソースコードは書かない
- **Codex**: `codex exec --sandbox workspace-write` で全実装を委譲
- hookは全て `command` type（Claudeトークン0）。`agent` type は原則使わない
- CLAUDE.md合計200行以内。rules/にはpathsフロントマター必須
- 詳細: `/kb-harness` で設計ナレッジベースを参照

## ハーネス設計テンプレ
```
.claude/
  settings.json       # PostToolUse(lint) + Stop(品質ゲート) + SessionStart(復旧) + PreToolUse(ガード)
  hooks/              # command hookのみ（APIゼロ）
  rules/              # pathsフロントマター必須。learned/に自動昇格
  agents/             # name=英語小文字+ハイフン
```

## 自律実行ルール（-p モード）
- `--worktree` 併用推奨
- スコープ厳密限定。関連改善はTODO記載のみ
- 同一エラー3回失敗 → 異なるアプローチ。さらに3回 → スキップ+TODO
- 既存テストを修正禁止。テスト失敗は実装側で解決
- コミットは意味のある単位で中間コミット

## 完了条件
- 既存テストパス（pytest）
- 自分の変更のlintエラー0（ruff）
- `/review --staged` を最終コミット後に実行
