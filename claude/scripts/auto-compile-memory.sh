#!/bin/bash
# Auto-compile playground-s6e4 memory notes after Claude Code stops.

PROJECT_DIR="$HOME/Projects/kaggle/playground-s6e4"
MEMORY_DIR="$HOME/.claude/projects/-Users-ykaneko-Projects-kaggle-playground-s6e4/memory"
COMPILED="$MEMORY_DIR/compiled.json"
LOG_FILE="/tmp/auto-compile-memory.log"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

mtime() {
    if stat -f '%m' "$1" >/dev/null 2>&1; then
        stat -f '%m' "$1"
    else
        stat -c '%Y' "$1"
    fi
}

canonical_path() {
    local path="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath "$path" 2>/dev/null
    else
        (cd "$path" 2>/dev/null && pwd -P)
    fi
}

main() {
    local project_context="${CLAUDE_PROJECT_DIR:-${PWD:-}}"
    local canonical_project canonical_context

    canonical_project="$(canonical_path "$PROJECT_DIR")"
    canonical_context="$(canonical_path "$project_context")"

    if [[ -z "$canonical_project" || "$canonical_context" != "$canonical_project" ]]; then
        log "skip: project is not playground-s6e4 (context=${project_context:-unknown})"
        return 0
    fi

    if [[ ! -d "$MEMORY_DIR" ]]; then
        log "skip: memory directory missing ($MEMORY_DIR)"
        return 0
    fi

    local latest_md latest_md_mtime compiled_mtime
    latest_md="$(
        find "$MEMORY_DIR" -type f -name '*.md' -print0 2>/dev/null \
            | xargs -0 stat -f '%m %N' 2>/dev/null \
            | sort -nr \
            | head -1 \
            | cut -d' ' -f2-
    )"

    if [[ -z "$latest_md" ]]; then
        log "skip: no markdown files in $MEMORY_DIR"
        return 0
    fi

    latest_md_mtime="$(mtime "$latest_md" 2>/dev/null || printf '0')"
    if [[ -f "$COMPILED" ]]; then
        compiled_mtime="$(mtime "$COMPILED" 2>/dev/null || printf '0')"
    else
        compiled_mtime=0
    fi

    if [[ "$latest_md_mtime" -le "$compiled_mtime" ]]; then
        log "skip: compiled.json is current (latest_md=$(basename "$latest_md"))"
        return 0
    fi

    log "recompile: detected $(basename "$latest_md") newer than compiled.json"

    cd "$PROJECT_DIR" || {
        log "error: cannot cd to $PROJECT_DIR"
        return 0
    }

    local compile_status=1
    if command -v uv >/dev/null 2>&1; then
        if MEMORY_DIR="$MEMORY_DIR" uv run python -m scripts.compile_memory >> "$LOG_FILE" 2>&1; then
            compile_status=0
        else
            log "error: uv compile failed; retrying with python3"
        fi
    fi

    if [[ "$compile_status" -ne 0 ]]; then
        if command -v python3 >/dev/null 2>&1; then
            if MEMORY_DIR="$MEMORY_DIR" python3 -m scripts.compile_memory >> "$LOG_FILE" 2>&1; then
                compile_status=0
            else
                log "error: python3 compile failed"
            fi
        else
            log "error: python3 not found"
        fi
    fi

    if [[ "$compile_status" -eq 0 ]]; then
        log "done: compiled=$COMPILED"
    else
        log "done: compile failed but hook exits 0"
    fi
    return 0
}

main "$@" || true
exit 0
