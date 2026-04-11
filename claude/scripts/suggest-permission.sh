#!/bin/bash
# PostToolUse hook: ツール実行が拒否された場合に許可追加を提案
# settings.jsonのPostToolUseに追加して使う
#
# 使い方: このスクリプトは情報提供のみ。実際の追加はユーザーが判断。
#
# 環境変数:
#   CLAUDE_TOOL_NAME: 使用されたツール名
#   CLAUDE_TOOL_INPUT: ツールの入力（JSONエスケープ済み）
#   CLAUDE_TOOL_OUTPUT: ツールの出力
#   CLAUDE_TOOL_STATUS: success/error

# 現時点ではログのみ（将来的に自動提案に拡張可能）
if [ "$CLAUDE_TOOL_STATUS" = "error" ] && echo "$CLAUDE_TOOL_OUTPUT" | grep -q "Permission.*denied\|has been denied"; then
    echo "[$(date)] Permission denied: $CLAUDE_TOOL_NAME - $CLAUDE_TOOL_INPUT" >> ~/.claude/logs/permission_denials.log
fi

exit 0
