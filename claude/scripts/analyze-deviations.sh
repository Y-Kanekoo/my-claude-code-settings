#!/bin/bash
# Stop hook: 出力ズレの学習エンジン
# deviations.mdを分析し、3回以上再発したパターンをlearned_rules.mdに昇格させる
#
# フロー:
#   検出(各フック) → 記録(deviations.md) → 学習(このスクリプト) → 防止(learned_rules.md)
#                                                                    ↓
#                                              次回の会話でClaudeが自動参照

set -uo pipefail

source "${HOME}/.claude/scripts/lib/deviation_recorder.sh" 2>/dev/null || exit 0

THRESHOLD=3  # この回数以上で「学習済みルール」に昇格

# === メモリディレクトリの取得 ===
MEMORY_DIR=$(_deviation_get_memory_dir) || exit 0
DEVIATION_LOG="$MEMORY_DIR/deviations.md"
LEARNED_RULES="$MEMORY_DIR/learned_rules.md"
MEMORY_INDEX="$MEMORY_DIR/MEMORY.md"

# deviations.mdがなければ何もしない
[ -f "$DEVIATION_LOG" ] || exit 0

# === パターン分析 ===
# タイプ別の出現回数を集計
TYPES_WITH_COUNT=$(grep "^## " "$DEVIATION_LOG" | sed 's/^## .* — //' | sort | uniq -c | sort -rn)

# 閾値を超えたパターンがなければ終了
FREQUENT_TYPES=$(echo "$TYPES_WITH_COUNT" | awk -v t="$THRESHOLD" '$1 >= t {$1=""; print substr($0,2)}')
[ -z "$FREQUENT_TYPES" ] && exit 0

# === learned_rules.md の初期化 ===
if [ ! -f "$LEARNED_RULES" ]; then
    cat > "$LEARNED_RULES" << 'HDR'
---
name: learned-rules
description: 出力ズレの再発パターンから自動抽出されたルール。Claudeが毎回参照して同じミスを防ぐ
type: feedback
---

# 学習済みルール（自動生成）

> このファイルはanalyze-deviations.shによって自動更新されます。
> 3回以上再発したパターンがルールとして記録されています。

HDR
    # MEMORY.mdにポインタ追加
    if [ -f "$MEMORY_INDEX" ]; then
        if ! grep -q "learned_rules.md" "$MEMORY_INDEX" 2>/dev/null; then
            echo "- [学習済みルール](learned_rules.md) — 再発パターンから自動抽出された防止ルール" >> "$MEMORY_INDEX"
        fi
    fi
fi

# === 各頻出パターンの処理 ===
PROMOTED_COUNT=0

while IFS= read -r TYPE; do
    [ -z "$TYPE" ] && continue

    # 既にルール化済みならスキップ
    if grep -qF "### $TYPE" "$LEARNED_RULES" 2>/dev/null; then
        # 件数だけ更新
        COUNT=$(grep -c "^## .* — $TYPE" "$DEVIATION_LOG" 2>/dev/null || echo "0")
        # 最終発生日を更新
        LAST_DATE=$(grep "^## .* — $TYPE" "$DEVIATION_LOG" | tail -1 | sed 's/^## \([0-9-]* [0-9:]*\) — .*/\1/')
        # 既存エントリの件数を更新（sed -i はmacOS互換）
        sed -i '' "s|発生回数: [0-9]*回.*($TYPE)|発生回数: ${COUNT}回 / 最終: ${LAST_DATE} ($TYPE)|" "$LEARNED_RULES" 2>/dev/null || true
        continue
    fi

    # 新規ルール: deviations.mdから該当パターンの最新の修正方法を取得
    COUNT=$(grep -c "^## .* — $TYPE" "$DEVIATION_LOG" 2>/dev/null || echo "0")
    LAST_FIX=$(grep -A3 "^## .* — $TYPE" "$DEVIATION_LOG" | grep "^\- \*\*修正\*\*:" | tail -1 | sed 's/^- \*\*修正\*\*: //')
    LAST_EXPECTED=$(grep -A3 "^## .* — $TYPE" "$DEVIATION_LOG" | grep "^\- \*\*期待\*\*:" | tail -1 | sed 's/^- \*\*期待\*\*: //')

    # ルールとして記録
    {
        echo "### $TYPE"
        echo "- 発生回数: ${COUNT}回 / 最終: $(date '+%Y-%m-%d') ($TYPE)"
        echo "- **ルール**: $LAST_EXPECTED"
        echo "- **対処法**: $LAST_FIX"
        echo ""
    } >> "$LEARNED_RULES"

    PROMOTED_COUNT=$((PROMOTED_COUNT + 1))
done <<< "$FREQUENT_TYPES"

# === レポート出力 ===
if [ "$PROMOTED_COUNT" -gt 0 ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "改善ループ: ${PROMOTED_COUNT}件の新ルールを学習しました"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "$FREQUENT_TYPES" | while IFS= read -r TYPE; do
        [ -z "$TYPE" ] && continue
        COUNT=$(grep -c "^## .* — $TYPE" "$DEVIATION_LOG" 2>/dev/null || echo "0")
        echo "  → $TYPE (${COUNT}回再発 → ルール化)"
    done
    echo "  📄 $LEARNED_RULES"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

exit 0
