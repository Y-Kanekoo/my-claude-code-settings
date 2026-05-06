#!/bin/bash
# PostToolUse(Bash) hook: テスト合格・提出ファイル生成時に自動コミット
# Stop hookとの重複防止: 直前コミットから60秒以内なら何もしない

PROJECT_DIR="$HOME/Projects/kaggle/playground-s6e4"
[ -d "$PROJECT_DIR/.git" ] || exit 0
cd "$PROJECT_DIR" || exit 0

# 重複防止: 直前コミットから60秒以内ならスキップ
LAST_COMMIT_TIME=$(git log -1 --format=%ct 2>/dev/null || echo 0)
NOW=$(date +%s)
if [ $((NOW - LAST_COMMIT_TIME)) -lt 60 ]; then
    exit 0
fi

# 変更がなければスキップ
if git diff --quiet && git diff --cached --quiet; then
    exit 0
fi

# stdin からツール情報を読む（PostToolUse hook形式）
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
OUTPUT=$(echo "$INPUT" | jq -r '.tool_response // ""' 2>/dev/null)

# テスト合格を検知
if echo "$COMMAND" | grep -qE "pytest|python -m pytest"; then
    if echo "$OUTPUT" | grep -qE "passed|PASSED"; then
        git add tests/ scripts/ src/ 2>/dev/null
        git commit -m "[test] テスト合格 — 自動コミット

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>" 2>/dev/null
        exit 0
    fi
fi

# 提出ファイル生成を検知
if [ -d "$PROJECT_DIR/submissions" ]; then
    LATEST_SUB=$(ls -t "$PROJECT_DIR/submissions"/*.csv 2>/dev/null | head -1)
    if [ -n "$LATEST_SUB" ]; then
        MTIME=$(stat -f%m "$LATEST_SUB" 2>/dev/null)
        if [ $((NOW - MTIME)) -lt 30 ]; then
            git add scripts/ src/ 2>/dev/null
            SUBNAME=$(basename "$LATEST_SUB")
            git commit -m "[submit] 提出ファイル生成: $SUBNAME — 自動コミット

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>" 2>/dev/null
            exit 0
        fi
    fi
fi

exit 0
