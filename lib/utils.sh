#!/usr/bin/env bash
# lib/utils.sh — Shared utility functions sourced by all pipeline modules.

# -----------------------------------------------------------------------------
# log_step <srr> <tag> <message>
# -----------------------------------------------------------------------------
log_step() {
    local srr="$1" tag="$2" msg="$3"
    local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
    local line="[${ts}] [${srr}] [${tag}] ${msg}"
    echo "$line"
    echo "$line" >> "${LOG_DIR}/${srr}.log"
}

# -----------------------------------------------------------------------------
# check_tool <name>
# -----------------------------------------------------------------------------
check_tool() {
    local tool="$1"
    if ! command -v "$tool" &>/dev/null; then
        echo "[ABORT] Tool not found in PATH: ${tool}"
        echo "        Activate the correct conda environment or install the package."
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# check_all_tools <tool> [<tool> ...]
# -----------------------------------------------------------------------------
check_all_tools() {
    local missing=0
    for tool in "$@"; do
        if ! command -v "$tool" &>/dev/null; then
            echo "[MISSING] ${tool}"
            (( missing++ )) || true
        else
            echo "  [OK] ${tool}"
        fi
    done
    if [[ "$missing" -gt 0 ]]; then
        echo "[ABORT] ${missing} required tool(s) not found."
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# disk_usage <label>
# -----------------------------------------------------------------------------
disk_usage() {
    local label="$1"
    local used avail
    used=$(du -sh . 2>/dev/null | cut -f1)
    avail=$(df -BG . 2>/dev/null | awk 'NR==2{ gsub("G","",$4); print $4 }')
    echo "[DISK] ${label} | dir used: ${used} | free: ${avail}G"
    if [[ -n "$avail" && "$avail" -lt "$DISK_WARN_GB" ]] 2>/dev/null; then
        echo "[WARN] Free space below ${DISK_WARN_GB} GB threshold."
    fi
}

# -----------------------------------------------------------------------------
# require_file <path> <hint>
# -----------------------------------------------------------------------------
require_file() {
    local path="$1" hint="$2"
    if [[ ! -f "$path" ]]; then
        echo "[ABORT] Required file missing: ${path}"
        echo "        ${hint}"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# require_dir <path> <hint>
# -----------------------------------------------------------------------------
require_dir() {
    local path="$1" hint="$2"
    if [[ ! -d "$path" ]]; then
        echo "[ABORT] Required directory missing: ${path}"
        echo "        ${hint}"
        exit 1
    fi
}
