#!/bin/bash
# GitHub情報をバックグラウンドでキャッシュ更新するスクリプト
# ステータスラインから呼ばれ、60秒以上経過していたら非同期で更新する

CACHE_DIR="${HOME}/.claude/cache"
CACHE_FILE="${CACHE_DIR}/gh-status.json"
LOCK_FILE="${CACHE_DIR}/gh-update.lock"
CACHE_TTL=60  # 秒

mkdir -p "$CACHE_DIR"

# キャッシュが新しければスキップ
if [ -f "$CACHE_FILE" ]; then
  AGE=$(( $(date +%s) - $(stat -f%m "$CACHE_FILE" 2>/dev/null || echo 0) ))
  [ "$AGE" -lt "$CACHE_TTL" ] && exit 0
fi

# 既に更新中ならスキップ（ロックファイルで排他制御）
if [ -f "$LOCK_FILE" ]; then
  LOCK_AGE=$(( $(date +%s) - $(stat -f%m "$LOCK_FILE" 2>/dev/null || echo 0) ))
  # 古いロック（120秒以上）は削除
  [ "$LOCK_AGE" -gt 120 ] && rm -f "$LOCK_FILE" || exit 0
fi

# ghコマンドがなければ空キャッシュを作成して終了
if ! command -v gh &>/dev/null; then
  echo '{}' > "$CACHE_FILE"
  exit 0
fi

# ロック取得
touch "$LOCK_FILE"

# バックグラウンドで更新（ステータスラインをブロックしない）
(
  DIR="${1:-.}"

  # gitリポジトリでなければ空キャッシュ
  if ! git -C "$DIR" rev-parse --git-dir &>/dev/null; then
    echo '{}' > "$CACHE_FILE"
    rm -f "$LOCK_FILE"
    exit 0
  fi

  BRANCH=$(git -C "$DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)
  PR_NUM=""
  CI_STATUS=""

  # 現在のブランチのopen PR番号を取得
  if [ -n "$BRANCH" ]; then
    PR_NUM=$(gh pr list --head "$BRANCH" --state open --json number --jq '.[0].number // empty' 2>/dev/null || echo "")
  fi

  # CIステータスを取得（PRがあればPRのチェック、なければ最新コミット）
  if [ -n "$PR_NUM" ]; then
    CI_STATUS=$(gh pr checks "$PR_NUM" --json 'state' --jq '
      [.[].state] |
      if any(. == "FAILURE" or . == "ERROR") then "fail"
      elif any(. == "PENDING" or . == "QUEUED" or . == "IN_PROGRESS") then "pending"
      elif all(. == "SUCCESS" or . == "SKIPPED") then "pass"
      else "none"
      end
    ' 2>/dev/null || echo "")
  fi

  # キャッシュ書き込み
  printf '{"pr":"%s","ci":"%s","branch":"%s","updated":%d}\n' \
    "$PR_NUM" "$CI_STATUS" "$BRANCH" "$(date +%s)" > "$CACHE_FILE"

  rm -f "$LOCK_FILE"
) &>/dev/null &

exit 0
