#!/bin/bash
# PreToolUse hook: Kaggle submission 実行直前に memory_check.py を呼び
# 過去の失敗パターンとマッチする構成を警告/ブロックする。
#
# 発動条件:
#   Bash tool で `kaggle competitions submit` を含むコマンドが実行されようとしている時
#
# 動作:
#   直近の submissions/*.csv を memory_check.py に渡して判定
#   severity=block → exit 2 で hook が tool use をブロック
#   severity=warn  → stderr に警告を出すが通す
#   該当なし       → 何もしない

set -uo pipefail

# stdin から hook イベント(JSON)を読む
INPUT=$(cat 2>/dev/null || echo "{}")

# jq が無い環境でも動くよう最小限の文字列検査
if ! echo "$INPUT" | grep -q 'kaggle competitions submit'; then
    exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$HOME/Projects/kaggle/playground-s6e4}"
[ -d "$PROJECT_DIR" ] || exit 0

# 直近の submissions/*.csv を特定
LATEST_SUB=$(ls -t "$PROJECT_DIR/submissions"/*.csv 2>/dev/null | head -1)
if [ -z "$LATEST_SUB" ]; then
    exit 0
fi

# memory_check.py が存在しなければスキップ
if [ ! -f "$PROJECT_DIR/scripts/memory_check.py" ]; then
    exit 0
fi

# 実行 (uv 優先、フォールバックで system python)
cd "$PROJECT_DIR" || exit 0
if command -v uv >/dev/null 2>&1; then
    OUTPUT=$(uv run python -m scripts.memory_check --csv "$LATEST_SUB" 2>&1)
elif command -v python3 >/dev/null 2>&1; then
    OUTPUT=$(python3 -m scripts.memory_check --csv "$LATEST_SUB" 2>&1)
else
    exit 0
fi
EXIT_CODE=$?

case "$EXIT_CODE" in
    0)
        # info レベル以下。通す。
        exit 0
        ;;
    2)
        # warn. stderr に出して通す
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        echo "memory_check: WARN (提出は許可)" >&2
        echo "$OUTPUT" >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        exit 0
        ;;
    1)
        # block. hook で tool 実行を止める (exit 2 = blocking error per Claude Code spec)
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        echo "memory_check: BLOCK (提出を中止)" >&2
        echo "$OUTPUT" >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        exit 2
        ;;
    *)
        # 想定外。通す (fail-open)
        echo "memory_check: エラー ($EXIT_CODE) — fail-open で通過" >&2
        exit 0
        ;;
esac
