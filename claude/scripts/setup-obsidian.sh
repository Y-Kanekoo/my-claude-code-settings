#!/bin/bash
# setup-obsidian.sh — Obsidian VaultにClaude Codeのナレッジベースをリンク
#
# 使い方:
#   setup-obsidian.sh                  # 既知のKBをリンク
#   setup-obsidian.sh --discover       # 新規kb-*を自動検出してリンク
#   setup-obsidian.sh --vault ~/MyVault # Vault場所を指定
#
# シンボリックリンクでClaude Code内のKBとCLAUDE.mdをObsidian Vaultに接続する。
# リアルタイム双方向反映（実体ファイルは~/.claude/側に残る）。

set -euo pipefail

# --- 設定 ---
VAULT_DIR="$HOME/Obsidian"
CLAUDE_DIR_NAME="Claude Code"
DISCOVER=false

# 引数解析
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault)
      VAULT_DIR="$2"
      shift 2
      ;;
    --discover)
      DISCOVER=true
      shift
      ;;
    -h|--help)
      echo "使い方: setup-obsidian.sh [--vault <path>] [--discover]"
      echo "  --vault <path>  Vaultディレクトリを指定（デフォルト: ~/Obsidian）"
      echo "  --discover      新規kb-*ディレクトリを自動検出"
      exit 0
      ;;
    *)
      echo "不明なオプション: $1"
      exit 1
      ;;
  esac
done

CLAUDE_BASE="$VAULT_DIR/$CLAUDE_DIR_NAME"
SETTINGS_DIR="$CLAUDE_BASE/設定"
KB_DIR="$CLAUDE_BASE/KB"

# --- KB名マッピング（kb-xxx → 表示名） ---
kb_display_name() {
  case "$1" in
    kb-python)          echo "Python" ;;
    kb-frontend)        echo "Frontend" ;;
    kb-docker)          echo "Docker" ;;
    kb-database)        echo "Database" ;;
    kb-git)             echo "Git" ;;
    kb-patterns)        echo "Patterns" ;;
    kb-troubleshooting) echo "Troubleshooting" ;;
    kb-kaggle)          echo "Kaggle" ;;
    *)                  echo "" ;;
  esac
}

# 既知のKBリスト
KNOWN_KBS="kb-python kb-frontend kb-docker kb-database kb-git kb-patterns kb-troubleshooting kb-kaggle"

# --- ヘルパー ---
create_symlink() {
  local target="$1"  # リンク先（実体）
  local link="$2"    # リンク元（Obsidian内に作成）

  if [ -L "$link" ]; then
    local current_target
    current_target=$(readlink "$link")
    if [ "$current_target" = "$target" ]; then
      echo "  スキップ: $(basename "$link") （既にリンク済み）"
      return 0
    else
      echo "  更新: $(basename "$link") → $target"
      rm "$link"
    fi
  elif [ -e "$link" ]; then
    echo "  警告: $(basename "$link") はシンボリックリンクではありません。スキップします"
    return 1
  else
    echo "  作成: $(basename "$link") → $target"
  fi

  ln -s "$target" "$link"
}

# --- メイン処理 ---
echo "=== Obsidian × Claude Code セットアップ ==="
echo "Vault: $VAULT_DIR"
echo ""

# Vaultディレクトリ作成
mkdir -p "$SETTINGS_DIR" "$KB_DIR"
echo "ディレクトリ構造を作成しました"

# --- CLAUDE.md リンク ---
echo ""
echo "--- 設定ファイル ---"
create_symlink "$HOME/.claude/CLAUDE.md" "$SETTINGS_DIR/Global-CLAUDE.md"

if [ -f "$HOME/Projects/CLAUDE.md" ]; then
  create_symlink "$HOME/Projects/CLAUDE.md" "$SETTINGS_DIR/Projects-CLAUDE.md"
fi

# --- KBリンク ---
echo ""
echo "--- ナレッジベース ---"

if [ "$DISCOVER" = true ]; then
  # 自動検出モード: skills/kb-* を全て検出
  for kb_dir in "$HOME/.claude/skills"/kb-*/; do
    [ -d "$kb_dir" ] || continue
    kb_name=$(basename "$kb_dir")
    display_name=$(kb_display_name "$kb_name")

    if [ -z "$display_name" ]; then
      # 未知のKB: kb-プレフィックスを除いて先頭大文字化
      display_name=$(echo "${kb_name#kb-}" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
      echo "  (新規発見) $kb_name → $display_name"
    fi

    create_symlink "$HOME/.claude/skills/$kb_name" "$KB_DIR/$display_name"
  done
else
  # 既知のKBのみリンク
  for kb_name in $KNOWN_KBS; do
    source_dir="$HOME/.claude/skills/$kb_name"
    display_name=$(kb_display_name "$kb_name")
    if [ -d "$source_dir" ]; then
      create_symlink "$source_dir" "$KB_DIR/$display_name"
    else
      echo "  スキップ: $kb_name （ディレクトリが存在しません）"
    fi
  done
fi

# --- 結果 ---
echo ""
echo "=== セットアップ完了 ==="
echo "Obsidianで $VAULT_DIR を開いてください"
echo ""
echo "検証: bash ~/.claude/scripts/validate-obsidian-links.sh"
