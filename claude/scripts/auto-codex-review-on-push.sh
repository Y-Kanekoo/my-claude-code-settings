#!/bin/bash
# git push 後に Codex で差分レビューを実行する PostToolUse hook
# 入力: PostToolUse の JSON (.tool_input.command, .tool_response 等)
# 出力: ログファイル + 端末への要約

set -uo pipefail

# === 共通ライブラリ ===
source "${HOME}/.claude/scripts/lib/timeout_compat.sh" 2>/dev/null || true

# === 入力解析 ===
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || true
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || true

# Bash 以外、または git push でなければスキップ
[[ "$TOOL_NAME" == "Bash" ]] || exit 0
echo "$COMMAND" | grep -qE '(^|[[:space:];|&])git[[:space:]]+push([[:space:]]|$)' || exit 0

# 中断された push はレビュー不要
INTERRUPTED=$(echo "$INPUT" | jq -r '.tool_response.interrupted // false' 2>/dev/null) || true
[[ "$INTERRUPTED" == "true" ]] && exit 0

# tool_response.exit_code が取れる場合は、非0なら push 失敗としてスキップ
EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // empty' 2>/dev/null) || true
if [[ -n "$EXIT_CODE" && "$EXIT_CODE" != "0" ]]; then
    exit 0
fi

# stderr に明確な失敗シグナルがあれば push 失敗としてスキップ
STDERR=$(echo "$INPUT" | jq -r '.tool_response.stderr // empty' 2>/dev/null) || true
if echo "$STDERR" | grep -qiE 'rejected|failed to push|fatal:|error:|Permission denied'; then
    exit 0
fi

# === デバウンス（30秒以内の連続push抑制） ===
DEBOUNCE_FILE="/tmp/.codex-push-review-last-run"
if [[ -f "$DEBOUNCE_FILE" ]]; then
    LAST_RUN=$(cat "$DEBOUNCE_FILE" 2>/dev/null || echo "0")
    NOW=$(date +%s)
    if (( NOW - LAST_RUN < 30 )); then
        exit 0
    fi
fi

# === codex CLI 確認 ===
command -v codex >/dev/null 2>&1 || exit 0

# === プロジェクトルート決定 ===
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR" || exit 0

# git リポジトリかチェック
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# 上流との差分が残っていれば push 未反映の可能性があるためスキップ
if git rev-parse --verify '@{u}' >/dev/null 2>&1; then
    UNPUSHED_COUNT=$(git log '@{u}..HEAD' --oneline 2>/dev/null | wc -l | tr -d ' ')
    [[ "$UNPUSHED_COUNT" -gt 0 ]] && exit 0
fi

# develop ブランチ存在確認、なければ origin/HEAD をベースに
BASE_REF="origin/develop"
git rev-parse --verify "$BASE_REF" >/dev/null 2>&1 || BASE_REF="origin/main"
git rev-parse --verify "$BASE_REF" >/dev/null 2>&1 || BASE_REF="origin/HEAD"
git rev-parse --verify "$BASE_REF" >/dev/null 2>&1 || exit 0

# ベースとの差分が空ならスキップ
DIFF_FILES=$(git diff --name-only "$BASE_REF"...HEAD 2>/dev/null | wc -l | tr -d ' ')
[[ "$DIFF_FILES" -eq 0 ]] && exit 0

# === デバウンス更新 ===
date +%s > "$DEBOUNCE_FILE" 2>/dev/null || true

# === 出力ファイル準備 ===
LOG_DIR="${HOME}/.claude/logs"
mkdir -p "$LOG_DIR"
TS=$(date +%Y%m%d_%H%M%S)
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
LOG_FILE="$LOG_DIR/codex-review-${BRANCH//\//_}-${TS}.md"

# === Codex 実行（バックグラウンド、タイムアウト120秒） ===
{
    echo "# Codex Review: $BRANCH vs $BASE_REF"
    echo ""
    echo "**実行時刻**: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "**変更ファイル数**: $DIFF_FILES"
    echo ""
    echo "## レビュー結果"
    echo ""
    timeout 120s codex review --base "$BASE_REF" 2>&1 || echo "[timeout または error]"
} > "$LOG_FILE" 2>&1

# === 端末用サマリ（簡潔に） ===
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Codex Push Review: $BRANCH vs $BASE_REF"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# P1/P2/P3 指摘の有無を抽出
if grep -qE '\[P[123]\]' "$LOG_FILE" 2>/dev/null; then
    P1_COUNT=$(grep -cE '\[P1\]' "$LOG_FILE" 2>/dev/null || echo 0)
    P2_COUNT=$(grep -cE '\[P2\]' "$LOG_FILE" 2>/dev/null || echo 0)
    P3_COUNT=$(grep -cE '\[P3\]' "$LOG_FILE" 2>/dev/null || echo 0)
    echo "⚠️  指摘あり: P1=${P1_COUNT}件, P2=${P2_COUNT}件, P3=${P3_COUNT}件"
    echo "   詳細: $LOG_FILE"
elif grep -qiE 'no.*finding|no.*tracked|LGTM' "$LOG_FILE" 2>/dev/null; then
    echo "✅ 指摘なし"
else
    echo "📝 レビュー保存: $LOG_FILE"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit 0
