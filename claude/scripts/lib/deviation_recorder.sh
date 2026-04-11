#!/bin/bash
# 出力ズレ記録の共通ライブラリ
# 全フックから呼び出し可能。プロジェクトのmemory/deviations.mdに3点セットを記録する。
#
# 使用方法:
#   source ~/.claude/scripts/lib/deviation_recorder.sh
#   record_deviation "TYPE" "期待した内容" "実際の結果" "修正方法"
#
# 環境変数:
#   CLAUDE_PROJECT_DIR: プロジェクトディレクトリ（自動検出フォールバックあり）

_deviation_get_memory_dir() {
    local project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"

    # パスを正規化（シンボリックリンク解決）
    project_dir=$(cd "$project_dir" 2>/dev/null && pwd -P) || return 1

    # Claude Codeのプロジェクトメモリパスに変換
    # $HOME/Projects/foo → -Users-username-Projects-foo
    local encoded
    encoded=$(echo "$project_dir" | sed 's|/|-|g')
    echo "${HOME}/.claude/projects/${encoded}/memory"
}

record_deviation() {
    local type="${1:?TYPE is required}"
    local expected="${2:?EXPECTED is required}"
    local actual="${3:?ACTUAL is required}"
    local fix="${4:?FIX is required}"

    local memory_dir
    memory_dir=$(_deviation_get_memory_dir) || return 1

    local deviation_log="$memory_dir/deviations.md"
    local memory_index="$memory_dir/MEMORY.md"

    mkdir -p "$memory_dir"

    # deviations.mdが存在しなければヘッダー作成
    if [ ! -f "$deviation_log" ]; then
        cat > "$deviation_log" << 'HDR'
---
name: output-deviations
description: 期待と異なる出力のパターン記録。同じミスの再発防止用
type: feedback
---

# 出力ズレ記録

HDR
        if [ -f "$memory_index" ]; then
            if ! grep -q "deviations.md" "$memory_index" 2>/dev/null; then
                echo "- [出力ズレ記録](deviations.md) — 期待/実際/修正の3点セット" >> "$memory_index"
            fi
        fi
    fi

    # === 重複排除（Codexレビュー指摘対応）===
    # fingerprint = type + expected + actual の先頭40文字
    local fingerprint="${type}|${expected:0:40}|${actual:0:40}"
    local dedup_file="$memory_dir/.deviation_dedup"
    local cooldown=300  # 5分間のクールダウン

    if [ -f "$dedup_file" ]; then
        local last_fingerprint last_time now_epoch
        last_fingerprint=$(head -1 "$dedup_file" 2>/dev/null)
        last_time=$(tail -1 "$dedup_file" 2>/dev/null)
        now_epoch=$(date +%s)

        if [ "$last_fingerprint" = "$fingerprint" ] && \
           [ -n "$last_time" ] && \
           [ $((now_epoch - last_time)) -lt $cooldown ]; then
            # 同一fingerprint + 5分以内 → スキップ（count更新のみ）
            return 0
        fi
    fi

    # fingerprintとタイムスタンプを記録
    echo "$fingerprint" > "$dedup_file"
    date +%s >> "$dedup_file"

    # 3点セットを記録
    {
        echo "## $(date '+%Y-%m-%d %H:%M') — $type"
        echo "- **期待**: $expected"
        echo "- **実際**: $actual"
        echo "- **修正**: $fix"
        echo ""
    } >> "$deviation_log"
}

# 記録件数を取得（分析用）
count_deviations_by_type() {
    local type="${1:?TYPE is required}"
    local memory_dir
    memory_dir=$(_deviation_get_memory_dir) || { echo "0"; return; }
    local deviation_log="$memory_dir/deviations.md"

    if [ -f "$deviation_log" ]; then
        grep -c "^## .* — $type" "$deviation_log" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# 全タイプの集計を取得
summarize_deviations() {
    local memory_dir
    memory_dir=$(_deviation_get_memory_dir) || return 1
    local deviation_log="$memory_dir/deviations.md"

    if [ ! -f "$deviation_log" ]; then
        echo "記録なし"
        return
    fi

    # タイプ別に集計（"## YYYY-MM-DD HH:MM — TYPE" から TYPE を抽出）
    grep "^## " "$deviation_log" | sed 's/^## .* — //' | sort | uniq -c | sort -rn
}
