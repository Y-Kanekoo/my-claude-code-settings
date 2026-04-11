#!/bin/bash
# stylish-statusline.sh - Claude Code custom status line (v5)
# Codexレビュー指摘対応 / セキュリティ改善 / コード整理
set -eo pipefail

# --- 定数 ---
CTX_BAR_WIDTH=8
RL_BAR_WIDTH=6
WARN_THRESHOLD=80
GRADIENT_MIDPOINT=50

# --- 色定義 ---
RST='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
WHITE='\033[37m'
MAGENTA='\033[35m'

# --- Brailleドット（空部分は薄ドット ⠂ で視認性向上）---
BRAILLE=('⠂' '⣀' '⣄' '⣤' '⣦' '⣶' '⣷' '⣿')

NOW=$(date +%s)

# --- デバッグ（STATUSLINE_DEBUG=1 で有効）---
debug() { [ "${STATUSLINE_DEBUG:-}" = "1" ] && printf '[statusline] %s\n' "$*" >&2; return 0; }

# --- stdin JSON → 1回のjqで全変数を抽出（stdinを直接パイプ）---
# NOTE: \x1f (Unit Separator) 区切りは、statusLine JSONの全フィールドが
# 単一行値（パス, モデル名, 数値）であることを前提としている。
SEP=$'\x1f'
parsed=$(jq -r --arg sep "$SEP" '[
  (.workspace.current_dir // ""),
  (.model.display_name // "unknown"),
  ((.context_window.used_percentage // 0) | tostring),
  ((.cost.total_cost_usd // 0) | tostring),
  ((.cost.total_lines_added // 0) | tostring),
  ((.cost.total_lines_removed // 0) | tostring),
  ((.cost.total_duration_ms // 0) | tostring),
  (if .worktree then (.worktree.name // "") else "" end),
  (if .vim then (.vim.mode // "") else "" end),
  (if .agent then (.agent.name // "") else "" end),
  ((.rate_limits.five_hour.used_percentage // -1) | tostring),
  ((.rate_limits.five_hour.resets_at // 0) | tostring),
  ((.rate_limits.seven_day.used_percentage // -1) | tostring),
  ((.rate_limits.seven_day.resets_at // 0) | tostring)
] | join($sep)' 2>/dev/null) || { debug "jqパース失敗"; exit 0; }

IFS="$SEP" read -r CWD MODEL PCT_RAW COST LINES_ADD LINES_DEL DURATION_MS \
  WT_NAME VIM_MODE AGENT_NAME \
  RL5H_PCT RL5H_RESET RL7D_PCT RL7D_RESET <<< "$parsed"

# --- effort level（settings.jsonから直接取得、キャッシュなし）---
EFFORT=$(jq -r '.effortLevel // ""' "$HOME/.claude/settings.json" 2>/dev/null) || EFFORT=""

# --- ヘルパー関数 ---

# 制御文字を除去し、バックスラッシュをエスケープ（printf '%b' 安全化）
sanitize() {
  local s="$1"
  s=$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\032\034-\037')
  s="${s//\\/\\\\}"
  printf '%s' "$s"
}

# 数値の整数部を安全に抽出（デフォルト値付き）
to_int() {
  local val="${1%.*}"; val="${val:-$2}"
  [[ "$val" =~ ^-?[0-9]+$ ]] && echo "$val" || echo "${2:-0}"
}

gradient_color() {
  local pct=$(to_int "$1" 0)
  [ "$pct" -lt 0 ] && pct=0; [ "$pct" -gt 100 ] && pct=100
  if [ "$pct" -lt "$GRADIENT_MIDPOINT" ]; then
    local r=$((pct * 5)); [ "$r" -gt 255 ] && r=255
    printf -v _GC '\033[38;2;%d;200;80m' "$r"
  else
    local g=$((200 - (pct - GRADIENT_MIDPOINT) * 4)); [ "$g" -lt 0 ] && g=0
    printf -v _GC '\033[38;2;255;%d;60m' "$g"
  fi
}

braille_bar() {
  local pct=$(to_int "$1" 0) width=${2:-$CTX_BAR_WIDTH}
  [ "$pct" -lt 0 ] && pct=0; [ "$pct" -gt 100 ] && pct=100
  _BB=""
  local i seg_start seg_end
  for ((i=0; i<width; i++)); do
    seg_start=$((i * 100 / width))
    seg_end=$(((i + 1) * 100 / width))
    if [ "$pct" -ge "$seg_end" ]; then
      _BB+="${BRAILLE[7]}"
    elif [ "$pct" -le "$seg_start" ]; then
      _BB+="${BRAILLE[0]}"
    else
      local range=$((seg_end - seg_start)) fill=$((pct - seg_start))
      local idx=$((fill * 7 / range))
      [ "$idx" -gt 7 ] && idx=7; [ "$idx" -lt 0 ] && idx=0
      _BB+="${BRAILLE[$idx]}"
    fi
  done
}

fmt_remaining() {
  local reset_at=$(to_int "$1" 0)
  local remain=$((reset_at - NOW))
  if [ "$remain" -le 0 ]; then _FR="reset"; return; fi
  local d=$((remain / 86400)) h=$(((remain % 86400) / 3600)) m=$(((remain % 3600) / 60))
  if [ "$d" -gt 0 ]; then _FR="${d}d${h}h"
  elif [ "$h" -gt 0 ]; then _FR="${h}h${m}m"
  else _FR="${m}m"; fi
}

# レートリミット表示部品を構築（結果は _RL_PART に格納）
build_rl_part() {
  local label="$1" pct_int=$(to_int "$2" -1) reset_raw="$3"
  _RL_PART=""
  [ "$pct_int" -lt 0 ] && return 1
  gradient_color "$pct_int"
  braille_bar "$pct_int" "$RL_BAR_WIDTH"
  local warn=""; [ "$pct_int" -ge "$WARN_THRESHOLD" ] && warn=" ⚠"
  local remain=""
  local reset_int=$(to_int "$reset_raw" 0)
  if [ "$reset_int" -gt 0 ]; then
    fmt_remaining "$reset_int"; remain=" ${DIM}${_FR}${RST}"
  fi
  _RL_PART="${DIM}${label}${RST} ${_GC}${_BB}${RST} ${pct_int}%${warn}${remain}"
}

# --- 動的文字列のサニタイズ ---
MODEL=$(sanitize "$MODEL")
WT_NAME=$(sanitize "$WT_NAME")
VIM_MODE=$(sanitize "$VIM_MODE")
AGENT_NAME=$(sanitize "$AGENT_NAME")

# --- 数値の正規化 ---
PCT=$(to_int "$PCT_RAW" 0)
LINES_ADD=$(to_int "$LINES_ADD" 0)
LINES_DEL=$(to_int "$LINES_DEL" 0)
DUR_SEC=$(( $(to_int "$DURATION_MS" 0) / 1000 ))

debug "model=$MODEL effort=$EFFORT pct=$PCT cost=$COST"

# ===== LINE1: ディレクトリ / ブランチ / モード =====
DIR_NAME=$(sanitize "${CWD##*/}")
if git_toplevel=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null); then
  REPO_NAME=$(sanitize "${git_toplevel##*/}")
  BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null) || BRANCH=""
  BRANCH=$(sanitize "$BRANCH")
  # NOTE: diff --quiet HEAD は未追跡ファイルを検出しない（パフォーマンス上の許容）
  DIRTY=""; git -C "$CWD" diff --quiet HEAD 2>/dev/null || DIRTY="*"
  if [ "$DIR_NAME" = "$REPO_NAME" ]; then
    LINE1="${BOLD}${WHITE}${DIR_NAME}${RST} ${CYAN}${BRANCH}${DIRTY}${RST}"
  else
    LINE1="${BOLD}${WHITE}${DIR_NAME}${RST} ${DIM}│${RST} ${CYAN}${REPO_NAME} ${BRANCH}${DIRTY}${RST}"
  fi
else
  LINE1="${BOLD}${WHITE}${DIR_NAME}${RST}"
fi

debug "branch=${BRANCH:-none} dirty=${DIRTY:-clean}"

# モードインジケータ（worktree / vim / agent）
MODE_PARTS=()
[ -n "$WT_NAME" ] && MODE_PARTS+=("${CYAN}wt:${WT_NAME}${RST}")
[ -n "$VIM_MODE" ] && MODE_PARTS+=("${GREEN}vim:${VIM_MODE}${RST}")
[ -n "$AGENT_NAME" ] && MODE_PARTS+=("${YELLOW}⚡${AGENT_NAME}${RST}")
if [ ${#MODE_PARTS[@]} -gt 0 ]; then
  MODE_STR=""
  for p in "${MODE_PARTS[@]}"; do
    [ -n "$MODE_STR" ] && MODE_STR+=" "
    MODE_STR+="$p"
  done
  LINE1+=" ${DIM}│${RST} ${MODE_STR}"
fi

# ===== LINE2: コンテキスト / モデル / effort =====
gradient_color "$PCT"; CTX_COLOR="$_GC"
braille_bar "$PCT" "$CTX_BAR_WIDTH"; CTX_BAR="$_BB"
CTX_WARN=""; [ "$PCT" -ge "$WARN_THRESHOLD" ] && CTX_WARN=" ⚠"

EFFORT_DISPLAY=""
case "$EFFORT" in
  max)    EFFORT_DISPLAY=" ${BOLD}${MAGENTA}★max${RST}" ;;
  high)   EFFORT_DISPLAY=" ${GREEN}●high${RST}" ;;
  medium) EFFORT_DISPLAY=" ${YELLOW}◐med${RST}" ;;
  low)    EFFORT_DISPLAY=" ${DIM}○low${RST}" ;;
esac

LINE2="${DIM}ctx${RST} ${CTX_COLOR}${CTX_BAR}${RST} ${PCT}%${CTX_WARN} ${DIM}│${RST} ${CYAN}${MODEL}${RST}${EFFORT_DISPLAY}"

# ===== LINE3: レートリミット =====
LINE3=""
RL_PARTS=()
build_rl_part "5h" "$RL5H_PCT" "$RL5H_RESET" && RL_PARTS+=("$_RL_PART")
build_rl_part "7d" "$RL7D_PCT" "$RL7D_RESET" && RL_PARTS+=("$_RL_PART")

if [ ${#RL_PARTS[@]} -gt 0 ]; then
  LINE3="${RL_PARTS[0]}"
  for ((i=1; i<${#RL_PARTS[@]}; i++)); do LINE3+=" ${DIM}│${RST} ${RL_PARTS[$i]}"; done
fi

# ===== LINE4: コスト / 変更行数 / 経過時間 =====
# COSTは -v で安全にawkへ渡す（インジェクション防止）
if [ -n "$COST" ] && [ "$COST" != "0" ]; then
  [[ "$COST" =~ ^-?[0-9]*\.?[0-9]+$ ]] || COST=0
  COST_FMT=$(awk -v c="$COST" 'BEGIN { c += 0; if (c < 1) printf "$%.3f", c; else printf "$%.2f", c }')
else
  COST_FMT="\$0.000"
fi

if [ "$LINES_ADD" != "0" ] || [ "$LINES_DEL" != "0" ]; then
  CHANGES="${GREEN}+${LINES_ADD}${RST}/${RED}-${LINES_DEL}${RST}"
else
  CHANGES="${DIM}--${RST}"
fi

if [ "$DUR_SEC" -ge 3600 ]; then
  TIME_FMT="$((DUR_SEC / 3600))h$(((DUR_SEC % 3600) / 60))m"
elif [ "$DUR_SEC" -ge 60 ]; then
  TIME_FMT="$((DUR_SEC / 60))m$((DUR_SEC % 60))s"
else
  TIME_FMT="${DUR_SEC}s"
fi

LINE4="${YELLOW}${COST_FMT}${RST} ${DIM}│${RST} ${CHANGES} ${DIM}│${RST} ${DIM}${TIME_FMT}${RST}"

# ===== 出力 =====
printf '%b\n' "$LINE1"
printf '%b\n' "$LINE2"
[ -n "$LINE3" ] && printf '%b\n' "$LINE3"
printf '%b\n' "$LINE4"
exit 0
