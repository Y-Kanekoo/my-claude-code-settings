#!/bin/bash
# Claude Code編集後にCodexでコードレビューを実行（最適化版）

set -uo pipefail

# === 共通ライブラリ読み込み ===
source "${HOME}/.claude/scripts/lib/timeout_compat.sh" 2>/dev/null || true

# === デバウンス機構 ===
# 前回のレビューから10秒以内はスキップ
DEBOUNCE_FILE="/tmp/.codex-review-last-run"
if [[ -f "$DEBOUNCE_FILE" ]]; then
    LAST_RUN=$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo "0")
    NOW=$(date +%s)
    if (( NOW - LAST_RUN < 10 )); then
        exit 0
    fi
fi

# 入力を読み取り
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || true

# ファイルパスがない場合はスキップ
[[ -z "$FILE_PATH" ]] && exit 0

# ファイルが存在しない場合はスキップ
[[ ! -f "$FILE_PATH" ]] && exit 0

# codexコマンドの存在確認
if ! command -v codex &> /dev/null; then
    exit 0
fi

# レビュー対象の拡張子（拡張版）
case "$FILE_PATH" in
    # スクリプト言語
    *.py|*.js|*.ts|*.tsx|*.jsx|*.rb|*.php|*.lua|*.pl|*.pm|*.r)
        ;;
    # コンパイル言語
    *.java|*.go|*.rs|*.swift|*.kt|*.scala|*.c|*.cpp|*.h|*.hpp)
        ;;
    # シェルスクリプト
    *.sh|*.bash|*.zsh)
        ;;
    # Web関連
    *.html|*.css|*.scss|*.sass|*.vue|*.svelte)
        ;;
    # SQL
    *.sql)
        ;;
    *)
        exit 0  # 対象外はスキップ
        ;;
esac

# 変更行数が少ない場合はスキップ（3行以下、新規ファイルは除外）
if git -C "$(dirname "$FILE_PATH")" rev-parse --git-dir &>/dev/null; then
  if git ls-files --error-unmatch "$FILE_PATH" &>/dev/null; then
    DIFF_LINES=$(git diff -- "$FILE_PATH" 2>/dev/null | grep -cE '^[+-][^+-]' || echo "0")
    if [[ "$DIFF_LINES" -le 3 ]]; then
      exit 0
    fi
  fi
fi

# テスト・設定ファイルはスキップ
BASENAME=$(basename "$FILE_PATH")
case "$BASENAME" in
    test_*|*_test.*|*.test.*|*.spec.*|*Test.java|*_spec.rb|conftest.py)
        exit 0
        ;;
esac
case "$FILE_PATH" in
    */__tests__/*|*/e2e/*|*.stories.*)
        exit 0
        ;;
esac
case "$FILE_PATH" in
    *.config.*|*.json|*.yaml|*.yml|*.toml|*.lock)
        exit 0
        ;;
esac

# プロジェクトディレクトリの決定（フォールバック付き）
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR" || exit 0

# デバウンスタイムスタンプ更新
date +%s > "$DEBOUNCE_FILE" 2>/dev/null || true

# 出力ヘッダー
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Codex Review: $(basename "$FILE_PATH")"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# === 共通ライブラリ読み込み（記録用） ===
source "${HOME}/.claude/scripts/lib/deviation_recorder.sh" 2>/dev/null || true

# Codex CLIでレビュー実行（タイムアウト30秒、read-onlyサンドボックス）
REVIEW_OUTPUT=$(timeout 30s codex exec --sandbox read-only --cd "$PROJECT_DIR" \
    "ファイル $FILE_PATH の変更をレビューしてください。
以下の観点で簡潔にコメント:
- バグの可能性
- セキュリティ問題
- パフォーマンス改善点
- コード品質
問題がなければ「LGTM」とだけ返答。" 2>&1 | head -80 || true)

echo "$REVIEW_OUTPUT"

# LGTM以外のレビュー結果を記録（改善ループの検出層）
if [ -n "$REVIEW_OUTPUT" ] && ! echo "$REVIEW_OUTPUT" | grep -qiE "LGTM|Not inside a trusted directory|trusted_directory"; then
    # レビュー指摘の最初の行を要約として取得
    FINDING=$(echo "$REVIEW_OUTPUT" | grep -v "^$" | head -3 | tr '\n' ' ' | cut -c1-200)
    record_deviation "codex-review-finding" \
        "LGTM（問題なし）" \
        "レビュー指摘: $FINDING" \
        "指摘事項を修正してから再コミット (file: $(basename "$FILE_PATH"))" 2>/dev/null || true
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit 0
