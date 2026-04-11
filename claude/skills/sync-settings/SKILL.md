---
name: sync-settings
description: Claude Code設定を公開リポジトリと双方向同期する
user-invocable: true
---

# Claude Code 設定同期スキル

`~/.claude/` の設定を公開リポジトリ `my-claude-code-settings` と双方向同期する。

## 使い方

| コマンド | 用途 |
|---------|------|
| `/sync-settings` | 差分表示のみ（dry-run） |
| `/sync-settings push` | ~/.claude/ → リポジトリへエクスポート |
| `/sync-settings pull` | リポジトリ → ~/.claude/ へインポート |

## Push（エクスポート）手順

1. **差分確認**: `~/.claude/` と `claude/` の差分を表示
2. **個人情報チェック**: `validate-dotfiles.sh` を実行
3. **コピー**: 変更されたファイルをリポジトリへ同期
4. **コミット+プッシュ**: 変更をGitHubへ反映

### 同期対象

| ソース | 宛先 |
|--------|------|
| `~/.claude/CLAUDE.md` | `claude/CLAUDE.md` |
| `~/.claude/settings.json` | `claude/settings.json` |
| `~/.claude/settings.local.json` | `claude/settings.local.json` |
| `~/.claude/commands/` | `claude/commands/` |
| `~/.claude/config/auto-commit.conf` | `claude/config/auto-commit.conf` |
| `~/.claude/scripts/` | `claude/scripts/` |
| `~/.claude/skills/` (data-status除外) | `claude/skills/` |
| `~/.claude/templates/harness/` | `claude/templates/harness/` |

### 同期対象外（PC固有・ランタイム）
- `projects/` — プロジェクト固有メモリ
- `sessions/`, `history.jsonl`, `logs/` — セッションデータ
- `data-status/` — プロジェクト固有スキル
- `notification_states.json` — ランタイム状態

## Pull（インポート）手順

1. リポジトリの最新を `git pull`
2. バックアップ: `~/.claude/` の現在の状態を確認
3. 差分のあるファイルのみ上書きコピー
4. 変更内容を報告

## 実装

```bash
REPO_DIR="$HOME/Projects/my-claude-code-settings"
CLAUDE_DIR="$HOME/.claude"

# 同期対象ディレクトリ
SYNC_DIRS=(commands config scripts skills templates)
SYNC_FILES=(CLAUDE.md settings.json settings.local.json)

# Push
sync_push() {
  # 個人情報チェック
  bash "$CLAUDE_DIR/scripts/validate-dotfiles.sh" "$REPO_DIR/claude/" || {
    echo "個人情報が検出されました。修正してから再実行してください。"
    return 1
  }

  # ファイル同期
  for f in "${SYNC_FILES[@]}"; do
    cp "$CLAUDE_DIR/$f" "$REPO_DIR/claude/$f"
  done

  # ディレクトリ同期（data-status除外）
  for d in "${SYNC_DIRS[@]}"; do
    rsync -av --exclude='data-status' "$CLAUDE_DIR/$d/" "$REPO_DIR/claude/$d/"
  done

  cd "$REPO_DIR" && git add -A && git diff --cached --stat
}

# Pull
sync_pull() {
  cd "$REPO_DIR" && git pull

  for f in "${SYNC_FILES[@]}"; do
    cp "$REPO_DIR/claude/$f" "$CLAUDE_DIR/$f"
  done

  for d in "${SYNC_DIRS[@]}"; do
    rsync -av "$REPO_DIR/claude/$d/" "$CLAUDE_DIR/$d/"
  done
}
```

## 注意事項
- Push前に必ず `validate-dotfiles.sh` が実行される（個人情報漏洩防止）
- `auto-commit-milestone.sh` と `post-validate-kaggle.sh` のPROJECT_DIRはリポジトリ側で汎用化済み。ローカル（~/.claude/scripts/）は実際のパスを保持してよい
- 新しいスキルを追加した場合、同期対象に自動的に含まれる（data-status除外）
