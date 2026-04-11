#!/bin/bash
# Claude回答完了時に自動コミット＆レビュー（改良版）
#
# 設定方法（優先順位順）:
#   1. 環境変数
#   2. ~/.claude/config/auto-commit.conf
#   3. デフォルト値
#
# 設定項目:
#   AUTO_COMMIT_MODE: "auto"(デフォルト) / "confirm" / "skip"
#   AUTO_COMMIT_MIN_LINES: レビュー実行の最小変更行数 (デフォルト: 5)
#   AUTO_COMMIT_PROTECTED_BRANCHES: 保護ブランチ (デフォルト: "main,master,develop")
#   AUTO_COMMIT_DETAIL_REVIEW_LINES: 詳細レビューの最小変更行数 (デフォルト: 50)

set -euo pipefail

# === 共通ライブラリ読み込み ===
source "${HOME}/.claude/scripts/lib/timeout_compat.sh" 2>/dev/null || true

# === 設定ファイル読み込み ===
CONFIG_FILE="${HOME}/.claude/config/auto-commit.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    set +u
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    set -u
fi

# === 設定（環境変数 > 設定ファイル > デフォルト） ===
MODE="${AUTO_COMMIT_MODE:-auto}"
MIN_LINES="${AUTO_COMMIT_MIN_LINES:-5}"
PROTECTED_BRANCHES="${AUTO_COMMIT_PROTECTED_BRANCHES:-main,master,develop}"
DETAIL_REVIEW_LINES="${AUTO_COMMIT_DETAIL_REVIEW_LINES:-50}"
LOG_DIR="${HOME}/.claude/logs"
LOG_FILE="${LOG_DIR}/auto-commit-$(date +%Y%m%d).log"
LOG_RETENTION_DAYS=30

# === ユーティリティ関数 ===
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg" >> "$LOG_FILE"
    echo "$msg"
}

log_section() {
    echo "" >> "$LOG_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$LOG_FILE"
    echo "$1" >> "$LOG_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$LOG_FILE"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# === 初期化 ===
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$PROJECT_DIR" || exit 0

# ログディレクトリ作成
mkdir -p "$LOG_DIR"

# === ログローテーション ===
find "$LOG_DIR" -name "auto-commit-*.log" -type f -mtime +${LOG_RETENTION_DAYS} -delete 2>/dev/null || true

# スキップモードの場合は即終了
if [[ "$MODE" == "skip" ]]; then
    exit 0
fi

# gitリポジトリでなければスキップ
git rev-parse --git-dir &>/dev/null || exit 0

# === 保護ブランチチェック ===
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
IFS=',' read -ra PROTECTED_ARRAY <<< "$PROTECTED_BRANCHES"
for branch in "${PROTECTED_ARRAY[@]}"; do
    if [[ "$CURRENT_BRANCH" == "$branch" ]]; then
        log "保護ブランチ($branch)のため自動コミットをスキップ"
        exit 0
    fi
done

# === 変更チェック ===
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    exit 0
fi

# codexコマンドの存在確認
if ! command -v codex &> /dev/null; then
    log "警告: codexコマンドが見つかりません。手動でコミットしてください。"
    exit 0
fi

# === 変更内容の分析 ===
CHANGED_LINES=$(git diff --numstat 2>/dev/null | awk '{sum+=$1+$2} END {print sum+0}')
STAGED_LINES=$(git diff --cached --numstat 2>/dev/null | awk '{sum+=$1+$2} END {print sum+0}')
UNTRACKED_COUNT=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
TOTAL_CHANGES=$((CHANGED_LINES + STAGED_LINES + UNTRACKED_COUNT * 10))

log "変更検出: ${CHANGED_LINES}行(diff) + ${STAGED_LINES}行(staged) + ${UNTRACKED_COUNT}ファイル(新規)"

# === ステージング（機密ファイルを除外） ===
git add -A
git reset HEAD -- '*.env' '*.env.*' '.env' '.env.*' 2>/dev/null || true
git reset HEAD -- 'credentials*.json' '*secret*' '*.pem' '*.key' 2>/dev/null || true

# === レビュー実行（コミット前） ===
REVIEW_RESULT=""
REVIEW_PASSED=true

if [[ $TOTAL_CHANGES -ge $MIN_LINES ]]; then
    log_section "Codex Review: コミット前レビュー"

    REVIEW_RESULT=$(timeout 60s codex exec --sandbox read-only --cd "$PROJECT_DIR" \
        "git diff --cached の変更をレビューしてください。
以下の観点で簡潔にコメント:
- 重大なバグの可能性
- セキュリティ問題
- 明らかな問題

問題がなければ「LGTM」とだけ返答。
重大な問題がある場合は「BLOCK:」で始めて理由を説明。" 2>&1 | head -30 || echo "レビュータイムアウト")

    echo "$REVIEW_RESULT"
    echo "$REVIEW_RESULT" >> "$LOG_FILE"

    # BLOCK判定（部分一致で検出）
    if echo "$REVIEW_RESULT" | grep -q 'BLOCK:'; then
        REVIEW_PASSED=false
        log "レビューでブロックされました。コミットを中止します。"
        git reset HEAD -- . >/dev/null 2>&1 || true
        exit 0
    fi
else
    log "変更が少ない(${TOTAL_CHANGES}行 < ${MIN_LINES}行)ためレビューをスキップ"
fi

# === 確認モード ===
if [[ "$MODE" == "confirm" ]]; then
    log "確認モード: 手動でコミットしてください"
    git reset HEAD -- . >/dev/null 2>&1 || true
    exit 0
fi

# === コミットメッセージ生成 ===
COMMIT_MSG=$(timeout 30s codex exec --sandbox read-only --cd "$PROJECT_DIR" \
    "git diff --cachedの変更内容を分析し、以下の形式でコミットメッセージを1行で生成:
[種別] 変更内容の要約
種別: feat/fix/refactor/docs/test/chore
例: [fix] ユーザー認証のバグを修正
コミットメッセージのみを出力し、説明は不要。" 2>&1 | grep -E '^\[' | head -1 || echo "")

# フォールバック
if [[ -z "$COMMIT_MSG" ]]; then
    COMMIT_MSG="[auto] Claude Code修正"
fi

# === コミット実行 ===
git commit -m "$COMMIT_MSG

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>" || {
    log "コミット失敗"
    exit 0
}

log_section "自動コミット完了: $COMMIT_MSG"

# === コミット後の詳細レビュー（大きな変更のみ） ===
if [[ $TOTAL_CHANGES -ge $DETAIL_REVIEW_LINES ]]; then
    log_section "Codex Review: 詳細レビュー"

    DETAIL_REVIEW=$(timeout 60s codex exec --sandbox read-only --cd "$PROJECT_DIR" \
        "git show HEAD の変更を詳細にレビューしてください。
以下の観点でコメント:
- アーキテクチャの改善点
- テストの必要性
- ドキュメント更新の必要性
改善提案があれば具体的に。" 2>&1 | head -50 || true)

    echo "$DETAIL_REVIEW"
    echo "$DETAIL_REVIEW" >> "$LOG_FILE"
fi

log "完了 - ログ: $LOG_FILE"

# === 設定リポジトリのドリフト検知 ===
SETTINGS_REPO="$HOME/Projects/my-claude-code-settings/claude"
if [ -d "$SETTINGS_REPO" ]; then
    DRIFT=""
    for target in skills scripts CLAUDE.md settings.json; do
        if [ -e "$HOME/.claude/$target" ]; then
            D=$(diff -rq "$HOME/.claude/$target" "$SETTINGS_REPO/$target" 2>/dev/null | grep -v "data-status" | head -3)
            [ -n "$D" ] && DRIFT="${DRIFT}${D}\n"
        fi
    done
    if [ -n "$DRIFT" ]; then
        osascript -e 'display notification "設定に未同期の変更があります。/sync-settings push で同期" with title "Claude Settings Drift"' 2>/dev/null || true
        log "設定ドリフト検知: $(echo -e "$DRIFT" | wc -l | tr -d ' ')件の差分"
    fi
fi

exit 0
