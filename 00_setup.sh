#!/usr/bin/env bash
# 00_setup.sh — Interactive compute-resource configurator.
# Prompts the user for thread counts and storage limits, validates the
# input, and writes the values directly into config.sh.
# Run this once before the first pipeline execution, or whenever the
# server's available resources change.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# prompt_int <variable_name> <prompt_text> <current_value> <min> <max>
# Displays a prompt with the current value and validates the response.
# Sets the variable named by $1 in the caller's scope.
# -----------------------------------------------------------------------------
prompt_int() {
    local var_name="$1" prompt_text="$2" current="$3" min="$4" max="$5"
    local value
    while true; do
        read -rp "  ${prompt_text} [current: ${current}, range: ${min}–${max}]: " value
        value="${value:-$current}"
        if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= min && value <= max )); then
            printf -v "$var_name" '%s' "$value"
            return
        fi
        echo "  Invalid input. Enter an integer between ${min} and ${max}."
    done
}

# -----------------------------------------------------------------------------
# prompt_bool <variable_name> <prompt_text> <current_value>
# Accepts y/yes/true or n/no/false. Falls back to current on empty input.
# Sets the variable to exactly "true" or "false".
# -----------------------------------------------------------------------------
prompt_bool() {
    local var_name="$1" prompt_text="$2" current="$3"
    local value
    while true; do
        read -rp "  ${prompt_text} [current: ${current}, y/n]: " value
        value="${value:-$current}"
        case "${value,,}" in
            y|yes|true)  printf -v "$var_name" 'true';  return ;;
            n|no|false)  printf -v "$var_name" 'false'; return ;;
            *)           echo "  Invalid input. Enter y (yes/true) or n (no/false)." ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# prompt_storage <variable_name> <prompt_text> <current_value>
# Accepts values like 50G, 200G, 1T. Falls back to current on empty input.
# -----------------------------------------------------------------------------
prompt_storage() {
    local var_name="$1" prompt_text="$2" current="$3"
    local value
    read -rp "  ${prompt_text} [current: ${current}]: " value
    value="${value:-$current}"
    if [[ "$value" =~ ^[0-9]+(G|T|M)$ ]]; then
        printf -v "$var_name" '%s' "$value"
    else
        echo "  Invalid format — keeping current value: ${current}"
        printf -v "$var_name" '%s' "$current"
    fi
}

# --- Load current values from config.sh so they appear as defaults ----------
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

# Detect logical CPU count for the upper bound
MAX_CPUS=$(nproc 2>/dev/null || sysctl -n hw.logicalcpu 2>/dev/null || echo 64)
AVAIL_GB=$(df -BG . 2>/dev/null | awk 'NR==2{ gsub("G","",$4); print $4 }' || echo 999)

echo ""
echo "========================================================"
echo " Lepidoptera RNA-seq Pipeline — Compute Resource Setup"
echo " Detected CPUs : ${MAX_CPUS}"
echo " Available disk: ${AVAIL_GB}G"
echo " Leave blank to keep the current value."
echo "========================================================"
echo ""
echo " SRA download / fasterq-dump"
prompt_int  NEW_T_DL    "Threads (THREADS_DOWNLOAD)" "$THREADS_DOWNLOAD" 1 "$MAX_CPUS"
echo ""
echo " FastQC"
prompt_int  NEW_T_FQC   "Threads (THREADS_FASTQC)"   "$THREADS_FASTQC"   1 "$MAX_CPUS"
echo ""
echo " Trimming (bbduk.sh)"
prompt_int  NEW_T_TRIM  "Threads (THREADS_TRIM)"     "$THREADS_TRIM"     1 "$MAX_CPUS"
echo ""
echo " STAR genome index build"
prompt_int  NEW_T_STAR  "Threads (THREADS_STAR)"     "$THREADS_STAR"     1 "$MAX_CPUS"
echo ""
echo " RSEM quantification"
prompt_int  NEW_T_RSEM  "Threads (THREADS_RSEM)"     "$THREADS_RSEM"     1 "$MAX_CPUS"
echo ""
echo " Storage"
prompt_storage NEW_SRA_SIZE "Max SRA download size (MAX_SRA_SIZE)" "$MAX_SRA_SIZE"
prompt_int  NEW_DISK_WARN "Disk warning threshold GB (DISK_WARN_GB)" "$DISK_WARN_GB" 1 9999

echo ""
echo " Trimming"
prompt_bool NEW_TRIMMING_ENABLED \
    "Enable adapter/quality trimming with bbduk (TRIMMING_ENABLED)" \
    "${TRIMMING_ENABLED:-true}"
echo ""
if [[ "$NEW_TRIMMING_ENABLED" == "true" ]]; then
    echo " bbduk.sh parameters (press Enter to keep current values)"
    prompt_int NEW_BBDUK_K      "Adapter k-mer length    (BBDUK_K)"       "${BBDUK_K:-23}"      10 31
    prompt_int NEW_BBDUK_MINK   "Min adapter k-mer       (BBDUK_MINK)"    "${BBDUK_MINK:-11}"    4 20
    prompt_int NEW_BBDUK_TRIMQ  "Quality trim threshold  (BBDUK_TRIMQ)"   "${BBDUK_TRIMQ:-20}"   1 40
    prompt_int NEW_BBDUK_MINLEN "Min read length         (BBDUK_MINLEN)"  "${BBDUK_MINLEN:-36}"  20 200
    echo ""
fi

echo "========================================================"
echo " Summary of new values:"
printf "  THREADS_DOWNLOAD : %s\n" "$NEW_T_DL"
printf "  THREADS_FASTQC   : %s\n" "$NEW_T_FQC"
printf "  THREADS_TRIM     : %s\n" "$NEW_T_TRIM"
printf "  THREADS_STAR     : %s\n" "$NEW_T_STAR"
printf "  THREADS_RSEM     : %s\n" "$NEW_T_RSEM"
printf "  MAX_SRA_SIZE     : %s\n" "$NEW_SRA_SIZE"
printf "  DISK_WARN_GB     : %s\n" "$NEW_DISK_WARN"
printf "  TRIMMING_ENABLED : %s\n" "$NEW_TRIMMING_ENABLED"
if [[ "$NEW_TRIMMING_ENABLED" == "true" ]]; then
    printf "  BBDUK_K          : %s\n" "$NEW_BBDUK_K"
    printf "  BBDUK_MINK       : %s\n" "$NEW_BBDUK_MINK"
    printf "  BBDUK_TRIMQ      : %s\n" "$NEW_BBDUK_TRIMQ"
    printf "  BBDUK_MINLEN     : %s\n" "$NEW_BBDUK_MINLEN"
fi
echo "========================================================"
read -rp " Write these values to config.sh? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo " Aborted — config.sh unchanged."
    exit 0
fi

# Rewrite compute-resource and trimming variables in config.sh using sed.
# The species table and non-interactive path variables are left untouched.
CONFIG="${SCRIPT_DIR}/config.sh"
sed -i \
    -e "s|^THREADS_DOWNLOAD=.*|THREADS_DOWNLOAD=${NEW_T_DL}|" \
    -e "s|^THREADS_FASTQC=.*|THREADS_FASTQC=${NEW_T_FQC}|" \
    -e "s|^THREADS_TRIM=.*|THREADS_TRIM=${NEW_T_TRIM}|" \
    -e "s|^THREADS_STAR=.*|THREADS_STAR=${NEW_T_STAR}|" \
    -e "s|^THREADS_RSEM=.*|THREADS_RSEM=${NEW_T_RSEM}|" \
    -e "s|^MAX_SRA_SIZE=.*|MAX_SRA_SIZE=\"${NEW_SRA_SIZE}\"|" \
    -e "s|^DISK_WARN_GB=.*|DISK_WARN_GB=${NEW_DISK_WARN}|" \
    -e "s|^TRIMMING_ENABLED=.*|TRIMMING_ENABLED=${NEW_TRIMMING_ENABLED}|" \
    "$CONFIG"

if [[ "$NEW_TRIMMING_ENABLED" == "true" ]]; then
    sed -i \
        -e "s|^BBDUK_K=.*|BBDUK_K=${NEW_BBDUK_K}|" \
        -e "s|^BBDUK_MINK=.*|BBDUK_MINK=${NEW_BBDUK_MINK}|" \
        -e "s|^BBDUK_TRIMQ=.*|BBDUK_TRIMQ=${NEW_BBDUK_TRIMQ}|" \
        -e "s|^BBDUK_MINLEN=.*|BBDUK_MINLEN=${NEW_BBDUK_MINLEN}|" \
        "$CONFIG"
fi

echo " config.sh updated successfully."
echo " Next steps:"
echo "   bash 01_build_references.sh"
echo "   python3 02_prepare_samples.py --input <RunTable.xlsx>"
echo "   bash 03_quantify.sh [--test]"
