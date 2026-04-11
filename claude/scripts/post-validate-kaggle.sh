#!/bin/bash
# PostToolUse hook: Bash実行後に提出ファイルとOOFを自動バリデーション
# エラー検出時はmemory/に自動記録（出力ズレの学習層）

# === 共通ライブラリ読み込み ===
source "${HOME}/.claude/scripts/lib/deviation_recorder.sh" 2>/dev/null || exit 0

# NOTE: 自分のプロジェクトパスに変更してください
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

[ -d "$PROJECT_DIR" ] || exit 0

# record_deviationは共通ライブラリから提供される
# CLAUDE_PROJECT_DIRがセットされていない場合のフォールバック
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PROJECT_DIR}"

# 提出ファイルチェック
if [ -d "$PROJECT_DIR/submissions" ]; then
    LATEST_SUB=$(ls -t "$PROJECT_DIR/submissions"/*.csv 2>/dev/null | head -1)
    if [ -n "$LATEST_SUB" ]; then
        MTIME=$(stat -f%m "$LATEST_SUB" 2>/dev/null)
        NOW=$(date +%s)
        AGE=$((NOW - MTIME))
        if [ $AGE -lt 60 ]; then
            RESULT=$(cd "$PROJECT_DIR" && bash scripts/validate_submission.sh 2>&1)
            if [ $? -ne 0 ]; then
                FILENAME=$(basename "$LATEST_SUB")
                record_deviation "submission分布異常" \
                    "Low 55-65%, Med 33-40%, High 2-5%" \
                    "$RESULT" \
                    "列順確認 or 閾値バイアス確認"
            fi
        fi
    fi
fi

# OOFチェック
if [ -d "$PROJECT_DIR/oof" ]; then
    LATEST_OOF=$(ls -t "$PROJECT_DIR/oof"/*_oof.npy 2>/dev/null | head -1)
    if [ -n "$LATEST_OOF" ]; then
        MTIME=$(stat -f%m "$LATEST_OOF" 2>/dev/null)
        NOW=$(date +%s)
        AGE=$((NOW - MTIME))
        if [ $AGE -lt 60 ]; then
            RESULT=$(cd "$PROJECT_DIR" && bash scripts/validate_oof.sh 2>&1)
            if echo "$RESULT" | grep -q "ERROR"; then
                OOFNAME=$(basename "$LATEST_OOF")
                record_deviation "OOF品質エラー" \
                    "shape=(630000,3), NaNなし, 値[0,1]" \
                    "$RESULT" \
                    "列順修正 or モデル再確認"
            fi
        fi
    fi
fi

exit 0
