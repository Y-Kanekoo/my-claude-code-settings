#!/bin/bash
# Project-wide CLI wrapper for recording failures into Claude memory.

set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)"
LIB_PATH="${SCRIPT_DIR}/lib/deviation_recorder.sh"

usage() {
    cat <<USAGE
Usage:
  ${SCRIPT_NAME} TYPE 期待 実際 修正 [--project PATH]

Records a failure/deviation using the shared deviation recorder.

Arguments:
  TYPE        失敗・ズレの種類
  期待        期待した内容
  実際        実際の結果
  修正        次回の修正方法

Options:
  --project PATH  記録対象のプロジェクトディレクトリ
                  未指定時は CLAUDE_PROJECT_DIR または pwd を使用
  -h, --help      このヘルプを表示

Example:
  ${SCRIPT_NAME} 'LB悪化' 'LB>=0.98061' 'LB=0.97998' 'seed多様化を2に戻す'
USAGE
}

fail_usage() {
    echo "Error: $1" >&2
    echo >&2
    usage >&2
    exit 2
}

PROJECT_DIR=""
ARGS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --project)
            shift
            [ "$#" -gt 0 ] || fail_usage "--project requires PATH"
            PROJECT_DIR="$1"
            shift
            ;;
        --project=*)
            PROJECT_DIR="${1#--project=}"
            [ -n "$PROJECT_DIR" ] || fail_usage "--project requires PATH"
            shift
            ;;
        --*)
            fail_usage "unknown option: $1"
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

[ "${#ARGS[@]}" -eq 4 ] || fail_usage "TYPE, 期待, 実際, 修正 are required"

if [ ! -f "$LIB_PATH" ]; then
    echo "Error: deviation recorder not found: $LIB_PATH" >&2
    exit 1
fi

source "$LIB_PATH"

export CLAUDE_PROJECT_DIR="${PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"

record_deviation "${ARGS[0]}" "${ARGS[1]}" "${ARGS[2]}" "${ARGS[3]}"
