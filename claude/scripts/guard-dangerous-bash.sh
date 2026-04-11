#!/bin/bash
# Bash実行前のガードレール（PreToolUseフック）
# denyパターンでは捕捉できない危険なコマンドパターンを検出・ブロック
# 注意: 文字列マッチングによるガードレールであり、完全な防御ではない

# set -e を使わない（jq失敗等で正常コマンドがブロックされるのを防ぐ）
set -uo pipefail

# === 共通ライブラリ読み込み ===
source "${HOME}/.claude/scripts/lib/deviation_recorder.sh" 2>/dev/null || true

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || true

[[ -z "$COMMAND" ]] && exit 0

# ブロック時に記録する関数
_guard_block() {
    local reason="$1"
    local cmd="$2"
    # 短縮表示（80文字まで）
    local short_cmd="${cmd:0:80}"
    record_deviation "guard-block" \
        "安全なコマンドのみ実行" \
        "危険なパターン検出: $reason (cmd: $short_cmd)" \
        "Claudeがより安全な代替コマンドを使用すること" 2>/dev/null || true
    echo "{\"decision\": \"block\", \"reason\": \"$reason\"}"
}

# === シェル実行パターンの検出 ===

# パイプ経由でのシェル実行（sh, bash, zsh, dash, フルパス含む）
if echo "$COMMAND" | grep -qE '\|\s*(/usr/bin/env\s+)?(ba|z|da)?sh(\s|$)'; then
  _guard_block "パイプ経由でのシェル実行は禁止されています" "$COMMAND"
  exit 0
fi
if echo "$COMMAND" | grep -qE '\|\s*/bin/(ba|z|da)?sh(\s|$)'; then
  _guard_block "パイプ経由でのシェル実行は禁止されています（フルパス）" "$COMMAND"
  exit 0
fi

# eval の使用を検出
if echo "$COMMAND" | grep -qE '(^|\s|;)eval\s'; then
  _guard_block "eval コマンドの使用は禁止されています" "$COMMAND"
  exit 0
fi

# /etc への書き込みを検出（リダイレクト、tee、cp、mv、sed -i）
if echo "$COMMAND" | grep -qE '>\s*/etc/'; then
  _guard_block "/etc への書き込みは禁止されています" "$COMMAND"
  exit 0
fi
if echo "$COMMAND" | grep -qE '(tee|cp|mv|install)\s+.*\s/etc/'; then
  _guard_block "/etc への書き込みは禁止されています" "$COMMAND"
  exit 0
fi
if echo "$COMMAND" | grep -qE 'sed\s+-i.*\s/etc/'; then
  _guard_block "/etc への sed -i は禁止されています" "$COMMAND"
  exit 0
fi

# source で外部スクリプトを実行
if echo "$COMMAND" | grep -qE '(^|\s|;)(source|\.).*https?://'; then
  _guard_block "リモートスクリプトの source は禁止されています" "$COMMAND"
  exit 0
fi

# curl/wget→シェル実行パターン（sh, bash, zsh, dash, python, perl, ruby 含む）
if echo "$COMMAND" | grep -qE '(curl|wget).*\|\s*(/usr/bin/env\s+)?(ba|z|da)?sh(\s|$)'; then
  _guard_block "リモートスクリプトの直接実行は禁止されています" "$COMMAND"
  exit 0
fi
if echo "$COMMAND" | grep -qE '(curl|wget).*\|\s*(python|perl|ruby|node)'; then
  _guard_block "リモートスクリプトのインタプリタ実行は禁止されています" "$COMMAND"
  exit 0
fi

# base64デコード→実行パターン
if echo "$COMMAND" | grep -qE '(base64|openssl\s+base64).*\|\s*(ba|z|da)?sh'; then
  _guard_block "base64デコード経由のシェル実行は禁止されています" "$COMMAND"
  exit 0
fi

# === rm の再帰削除パターン（フラグ順序を問わず検出） ===
if echo "$COMMAND" | grep -qE '(^|\s|;|&&|\|\|)rm\s' && echo "$COMMAND" | grep -qE '\s-[a-zA-Z]*[rR]'; then
  _guard_block "rm の再帰削除は禁止されています" "$COMMAND"
  exit 0
fi
if echo "$COMMAND" | grep -qE '(^|\s|;|&&|\|\|)rm\s.*--recursive'; then
  _guard_block "rm の再帰削除は禁止されています" "$COMMAND"
  exit 0
fi

# === find -exec 経由の危険なコマンド ===
if echo "$COMMAND" | grep -qE 'find\s.*-exec\s.*rm\s'; then
  _guard_block "find -exec 経由の rm は禁止されています" "$COMMAND"
  exit 0
fi

# === python -c の危険なパターン ===
if echo "$COMMAND" | grep -qE "python3?\s+-c\s+.*(subprocess|os\.system|os\.popen|os\.exec|shutil\.rmtree|os\.remove|os\.unlink|os\.rmdir|__import__)"; then
  _guard_block "Python経由の危険な操作は禁止されています" "$COMMAND"
  exit 0
fi

# === node -e の危険なパターン ===
if echo "$COMMAND" | grep -qE "node\s+-e\s+.*(child_process|execSync|spawnSync|rmSync|unlinkSync|rmdirSync)"; then
  _guard_block "Node.js経由の危険な操作は禁止されています" "$COMMAND"
  exit 0
fi

# === curl/wget によるファイル送信パターン ===
if echo "$COMMAND" | grep -qE '(curl|wget).*(-d\s+@|-F\s+.*=@|--data.*@|--upload-file).*(\.env|\.ssh|\.aws|\.gnupg|credentials|secret|\.pem|\.key)'; then
  _guard_block "機密ファイルの外部送信は禁止されています" "$COMMAND"
  exit 0
fi

exit 0
