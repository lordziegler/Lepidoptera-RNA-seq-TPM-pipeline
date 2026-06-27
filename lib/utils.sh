#!/usr/bin/env bash
# Shared utilities sourced by all pipeline modules.

log_step() {
    local srr="$1" tag="$2" msg="$3"
    local ts line
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    line="[${ts}] [${srr}] [${tag}] ${msg}"
    echo "$line"
    mkdir -p "$LOG_DIR"
    echo "$line" >> "${LOG_DIR}/${srr}.log"
}

check_tools() {
    local missing=0
    for tool in "$@"; do
        if ! command -v "$tool" &>/dev/null; then
            echo "[MISSING] ${tool}"
            (( missing++ )) || true
        else
            echo "[OK] ${tool}"
        fi
    done
    if [[ "$missing" -gt 0 ]]; then
        echo "[ABORT] ${missing} required tool(s) not found in PATH."
        echo "        Activate the conda environment: conda activate lepidoptera-rnaseq"
        exit 1
    fi
}

disk_usage() {
    local label="$1"
    local used avail
    used="$(du -sh . 2>/dev/null | cut -f1)"
    avail="$(df -BG . 2>/dev/null | awk 'NR==2{ gsub("G","",$4); print $4 }')"
    echo "[DISK] ${label} | used: ${used} | free: ${avail}G"
    if [[ -n "$avail" ]] && (( avail < DISK_WARN_GB )); then
        echo "[WARN] Free space (${avail}G) below threshold (${DISK_WARN_GB}G)."
    fi
}

normalize_layout() {
    local raw
    raw="$(echo "$1" | tr '[:lower:]' '[:upper:]' | tr -d '\r' | sed 's/[-_]/ /g' | xargs)"
    case "$raw" in
        PAIRED|"PAIRED END"|PE) echo "PAIRED" ;;
        SINGLE|"SINGLE END"|SE) echo "SINGLE" ;;
        *) echo "[ABORT] Unknown library layout: '${1}'" >&2; return 1 ;;
    esac
}

require_file() {
    local path="$1" hint="$2"
    if [[ ! -f "$path" ]]; then
        echo "[ABORT] Required file missing: ${path}"
        [[ -n "$hint" ]] && echo "        ${hint}"
        exit 1
    fi
}

require_dir() {
    local path="$1" hint="$2"
    if [[ ! -d "$path" ]]; then
        echo "[ABORT] Required directory missing: ${path}"
        [[ -n "$hint" ]] && echo "        ${hint}"
        exit 1
    fi
}
