#!/bin/bash
# validate-obsidian-links.sh — Obsidian Vault内のシンボリックリンク検証
#
# 使い方:
#   validate-obsidian-links.sh [vault_path]
#   validate-obsidian-links.sh ~/Obsidian   # デフォルト
#
# 終了コード: 0=問題なし, 1=問題あり

set -eo pipefail

# --- 設定 ---
VAULT_DIR="${1:-$HOME/Obsidian}"
CLAUDE_DIR="$VAULT_DIR/Claude Code"
ERRORS=0
WARNINGS=0

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

print_warn() {
  echo "  ! $1"
  WARNINGS=$((WARNINGS + 1))
}

# シンボリックリンクを検証する共通関数
check_file_link() {
  local link_path="$1"
  local expected_target="$2"
  local link_name
  link_name=$(basename "$link_path")

  if [ ! -L "$link_path" ]; then
    print_fail "$link_name: シンボリックリンクが存在しません"
    return 1
  fi

  local actual_target
  actual_target=$(readlink "$link_path")
  if [ "$actual_target" != "$expected_target" ]; then
    print_fail "$link_name: リンク先が不正 (期待: $expected_target, 実際: $actual_target)"
    return 1
  fi

  if [ ! -e "$link_path" ]; then
    print_fail "$link_name: リンク先が存在しません → $expected_target"
    return 1
  fi

  print_ok "$link_name → $expected_target"
  return 0
}

check_dir_link() {
  local link_path="$1"
  local expected_target="$2"
  local link_name
  link_name=$(basename "$link_path")

  if ! check_file_link "$link_path" "$expected_target"; then
    return 1
  fi

  # .mdファイルの存在チェック（check_file_linkのprint_okを上書き）
  local md_count
  md_count=$(find -L "$link_path" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$md_count" -eq 0 ]; then
    print_warn "$link_name: .mdファイルが見つかりません（空のKB）"
  fi
  return 0
}

# --- チェック0: Vault存在確認 ---
print_header "Vault存在確認"
if [ ! -d "$VAULT_DIR" ]; then
  print_fail "Vaultディレクトリが存在しません: $VAULT_DIR"
  echo ""
  echo "  setup-obsidian.sh を先に実行してください"
  exit 1
fi
print_ok "Vault: $VAULT_DIR"

if [ ! -d "$CLAUDE_DIR" ]; then
  print_fail "Claude Codeディレクトリが存在しません: $CLAUDE_DIR"
  exit 1
fi
print_ok "Claude Code: $CLAUDE_DIR"

# --- チェック1: ファイルリンクの検証 ---
print_header "ファイルリンク検証"
check_file_link "$CLAUDE_DIR/設定/Global-CLAUDE.md" "$HOME/.claude/CLAUDE.md"
check_file_link "$CLAUDE_DIR/設定/Projects-CLAUDE.md" "$HOME/Projects/CLAUDE.md"

# --- チェック2: KBディレクトリリンクの検証 ---
print_header "KBディレクトリリンク検証"
check_dir_link "$CLAUDE_DIR/KB/Python" "$HOME/.claude/skills/kb-python"
check_dir_link "$CLAUDE_DIR/KB/Frontend" "$HOME/.claude/skills/kb-frontend"
check_dir_link "$CLAUDE_DIR/KB/Docker" "$HOME/.claude/skills/kb-docker"
check_dir_link "$CLAUDE_DIR/KB/Database" "$HOME/.claude/skills/kb-database"
check_dir_link "$CLAUDE_DIR/KB/Git" "$HOME/.claude/skills/kb-git"
check_dir_link "$CLAUDE_DIR/KB/Patterns" "$HOME/.claude/skills/kb-patterns"
check_dir_link "$CLAUDE_DIR/KB/Troubleshooting" "$HOME/.claude/skills/kb-troubleshooting"
check_dir_link "$CLAUDE_DIR/KB/Kaggle" "$HOME/.claude/skills/kb-kaggle"

# --- チェック3: 未リンクのKBを検出 ---
print_header "未リンクKB検出"
unlinked=0
for kb_dir in "$HOME/.claude/skills"/kb-*/; do
  [ -d "$kb_dir" ] || continue
  kb_name=$(basename "$kb_dir")

  # Vault内にこのKBへのリンクがあるか
  found=false
  for link in "$CLAUDE_DIR/KB"/*/; do
    [ -L "${link%/}" ] || continue
    link_target=$(readlink "${link%/}")
    if [ "$link_target" = "$HOME/.claude/skills/$kb_name" ]; then
      found=true
      break
    fi
  done

  if [ "$found" = false ]; then
    print_warn "未リンクのKB: $kb_name → setup-obsidian.sh --discover で追加可能"
    unlinked=$((unlinked + 1))
  fi
done
if [ "$unlinked" -eq 0 ]; then
  print_ok "すべてのKBがリンク済み"
fi

# --- 結果 ---
print_header "結果"
if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo "  すべてのチェックに合格しました ✓"
  exit 0
elif [ "$ERRORS" -eq 0 ]; then
  echo "  $WARNINGS 件の警告があります（エラーなし）"
  exit 0
else
  echo "  $ERRORS 件のエラー、$WARNINGS 件の警告"
  exit 1
fi
