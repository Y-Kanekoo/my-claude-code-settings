#!/bin/bash
# validate-dotfiles.sh — dotfiles共有前の個人情報チェック
# 対象ディレクトリ内のファイルにハードコードされた個人情報がないか検証する
#
# 使い方:
#   validate-dotfiles.sh [対象ディレクトリ]
#   validate-dotfiles.sh ~/.claude    # デフォルト
#
# 終了コード: 0=問題なし, 1=個人情報検出

set -euo pipefail

# --- 設定 ---
TARGET_DIR="${1:-$HOME/.claude}"
ERRORS=0

# 検出する個人情報パターン（正規表現）
PERSONAL_PATTERNS=(
  "/Users/$(whoami)/"          # macOS ハードコードパス
  "/home/$(whoami)/"           # Linux ハードコードパス
)

# dotfiles対象外（検査スキップ）のディレクトリ
EXCLUDE_DIRS=(
  "debug"
  "plans"
  "todos"
  "sessions"
  "plugins"
  "cache"
  "file-history"
  "backups"
  "projects"
  "config"
  "logs"
  "shell-snapshots"
  "data-status"        # プロジェクト固有スキル（dotfiles対象外）
)

# 除外するファイルパターン
EXCLUDE_FILES=(
  "*.jsonl"
  "validate-dotfiles.sh"       # 自分自身は除外
)

# .gitignore に必須のエントリ
REQUIRED_GITIGNORE=(
  "*.jsonl"
  "debug/"
  "history.jsonl"
)

# --- ヘルパー ---
print_header() {
  echo ""
  echo "===== $1 ====="
}

print_ok() {
  echo "  ✓ $1"
}

print_fail() {
  echo "  ✗ $1"
  ERRORS=$((ERRORS + 1))
}

# --- チェック1: 個人情報パターンの検出 ---
print_header "個人情報パターンチェック: $TARGET_DIR"

# 除外パターンをgrep用に組み立て
GREP_EXCLUDE_ARGS=()
for dir in "${EXCLUDE_DIRS[@]}"; do
  GREP_EXCLUDE_ARGS+=(--exclude-dir="$dir")
done
for pat in "${EXCLUDE_FILES[@]}"; do
  GREP_EXCLUDE_ARGS+=(--exclude="$pat")
done

for pattern in "${PERSONAL_PATTERNS[@]}"; do
  # バイナリファイルを除外して検索
  matches=$(grep -rn "${GREP_EXCLUDE_ARGS[@]}" --include="*.sh" --include="*.md" --include="*.json" --include="*.yaml" --include="*.yml" --include="*.toml" "$pattern" "$TARGET_DIR" 2>/dev/null || true)

  if [ -n "$matches" ]; then
    print_fail "パターン「${pattern}」が検出されました:"
    echo "$matches" | while IFS= read -r line; do
      echo "    $line"
    done
  else
    print_ok "パターン「${pattern}」: 検出なし"
  fi
done

# --- チェック2: .gitignore の必須エントリ ---
GITIGNORE_FILE="$TARGET_DIR/.gitignore"
if [ -f "$GITIGNORE_FILE" ]; then
  print_header ".gitignore 必須エントリチェック: $GITIGNORE_FILE"
  for entry in "${REQUIRED_GITIGNORE[@]}"; do
    if grep -qF "$entry" "$GITIGNORE_FILE" 2>/dev/null; then
      print_ok ".gitignore に「${entry}」あり"
    else
      print_fail ".gitignore に「${entry}」がありません"
    fi
  done
else
  # dotfilesリポジトリ内の.gitignoreも探す
  DOTFILES_GITIGNORE="$HOME/claude-dotfiles/.gitignore"
  if [ -f "$DOTFILES_GITIGNORE" ]; then
    print_header ".gitignore 必須エントリチェック: $DOTFILES_GITIGNORE"
    for entry in "${REQUIRED_GITIGNORE[@]}"; do
      if grep -qF "$entry" "$DOTFILES_GITIGNORE" 2>/dev/null; then
        print_ok ".gitignore に「${entry}」あり"
      else
        print_fail ".gitignore に「${entry}」がありません"
      fi
    done
  else
    echo ""
    echo "  (情報) .gitignore が見つかりません。dotfilesリポジトリ作成後に再実行してください"
  fi
fi

# --- 結果 ---
print_header "結果"
if [ "$ERRORS" -eq 0 ]; then
  echo "  すべてのチェックに合格しました ✓"
  exit 0
else
  echo "  $ERRORS 件の問題が検出されました ✗"
  exit 1
fi
