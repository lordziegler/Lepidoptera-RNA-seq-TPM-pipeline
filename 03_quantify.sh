#!/usr/bin/env bash
# 03_quantify.sh — Per-sample quantification loop.
# Reads samples.tsv and for each accession runs: prefetch → fasterq-dump →
# FastQC (raw) → bbduk (optional) → FastQC (clean) → MultiQC (clean) → RSEM+STAR.
# Intermediate files are deleted immediately after each step is confirmed.
# Set TRIMMING_ENABLED=false in config.sh to skip bbduk and pass raw FASTQ
# directly to STAR/RSEM.
#
# Usage:
#   bash 03_quantify.sh           # full run
#   bash 03_quantify.sh --test    # 500 000 reads/sample for validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"
source "${SCRIPT_DIR}/lib/cleanup.sh"

# --- Argument parsing --------------------------------------------------------
TEST_MODE=false
TEST_READS=""

for arg in "$@"; do
    case "$arg" in
        --test)
            TEST_MODE=true
            TEST_READS="-X 500000"
            echo "[INFO] Test mode — fasterq-dump limited to 500,000 reads per sample."
            ;;
        *)
            echo "[ABORT] Unknown argument: ${arg}"
            echo "Usage: bash 03_quantify.sh [--test]"
            exit 1
            ;;
    esac
done

# --- Pre-flight checks -------------------------------------------------------
_check_tools=(prefetch fasterq-dump fastqc multiqc STAR rsem-calculate-expression)
[[ "${TRIMMING_ENABLED:-true}" == "true" ]] && _check_tools+=(bbduk.sh)
check_all_tools "${_check_tools[@]}" || true
unset _check_tools

require_file "$SAMPLES_TSV" "Run: python3 02_prepare_samples.py --input <RunTable.xlsx>"

mkdir -p sra fastq clean_fastq "$TMP_DIR" fastqc_out multiqc_out rsem_results "$LOG_DIR"

disk_usage "pipeline-start"

# =============================================================================
# INTERNAL FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# resolve_reference_paths <species>
# Sets globals STAR_INDEX and RSEM_REF for the given species key.
# Aborts when either index is absent (run 01_build_references.sh first).
# -----------------------------------------------------------------------------
resolve_reference_paths() {
    local species="$1"
    STAR_INDEX="${REFERENCES_DIR}/${species}/STAR_genome_index"
    RSEM_REF="${REFERENCES_DIR}/${species}/rsem_ref"
    require_dir  "$STAR_INDEX"        "Run: bash 01_build_references.sh"
    require_file "${RSEM_REF}.grp"    "Run: bash 01_build_references.sh"
}

# -----------------------------------------------------------------------------
# step_prefetch <srr>
# Downloads the SRA archive. Skips if the file is already present.
# Populates global SRA_PATH with the resolved file location.
# -----------------------------------------------------------------------------
step_prefetch() {
    local srr="$1"
    local sra_a="sra/${srr}/${srr}.sra"
    local sra_b="sra/${srr}.sra"

    if [[ ! -f "$sra_a" && ! -f "$sra_b" ]]; then
        log_step "$srr" "PREFETCH" "Downloading from NCBI SRA ..."
        disk_usage "pre-prefetch [${srr}]"
        prefetch "$srr" \
            --output-directory sra \
            --max-size "$MAX_SRA_SIZE" \
            2>&1 | tee "${LOG_DIR}/${srr}_prefetch.log"
        if [[ ! -f "$sra_a" && ! -f "$sra_b" ]]; then
            log_step "$srr" "ERROR" "prefetch produced no .sra file — check log."
            return 1
        fi
    else
        log_step "$srr" "PREFETCH" "SRA file already present — skipping."
    fi

    if   [[ -f "$sra_a" ]]; then SRA_PATH="$sra_a"
    elif [[ -f "$sra_b" ]]; then SRA_PATH="$sra_b"
    else
        log_step "$srr" "ERROR" "SRA file not found after prefetch."
        return 1
    fi
}

# -----------------------------------------------------------------------------
# step_fasterq_dump <srr> <layout>
# Converts the SRA archive to FASTQ. Skips if output files already exist.
# Deletes the .sra file on success. Populates globals RAW_1, RAW_2, RAW_S.
# -----------------------------------------------------------------------------
step_fasterq_dump() {
    local srr="$1" layout="$2"
    RAW_1="fastq/${srr}_1.fastq"
    RAW_2="fastq/${srr}_2.fastq"
    RAW_S="fastq/${srr}.fastq"

    local already_done=false
    if [[ "$layout" == "PAIRED" && -f "$RAW_1" && -f "$RAW_2" ]]; then
        already_done=true
    elif [[ "$layout" == "SINGLE" && -f "$RAW_S" ]]; then
        already_done=true
    fi

    if [[ "$already_done" == false ]]; then
        if [[ "$TEST_MODE" == true ]]; then
            log_step "$srr" "FASTQ-DUMP" "Converting SRA → FASTQ (${layout}) [Test mode] ..."
            disk_usage "pre-fastq-dump [${srr}]"
            fastq-dump "$SRA_PATH" \
                --outdir fastq \
                --split-3 \
                ${TEST_READS} \
                2>&1 | tee "${LOG_DIR}/${srr}_fastq_dump.log"
        else
            log_step "$srr" "FASTERQ" "Converting SRA → FASTQ (${layout}) ..."
            disk_usage "pre-fasterq [${srr}]"
            fasterq-dump "$SRA_PATH" \
                --outdir  fastq \
                --temp    "$TMP_DIR" \
                --split-3 \
                --threads "$THREADS_DOWNLOAD" \
                2>&1 | tee "${LOG_DIR}/${srr}_fasterq.log"
        fi
    else
        log_step "$srr" "FASTERQ" "Raw FASTQ already present — skipping."
    fi

    if [[ "$layout" == "PAIRED" ]]; then
        if [[ ! -f "$RAW_1" || ! -f "$RAW_2" ]]; then
            log_step "$srr" "ERROR" "Paired FASTQ missing after conversion."
            return 1
        fi
    else
        if [[ ! -f "$RAW_S" ]]; then
            log_step "$srr" "ERROR" "Single-end FASTQ missing after conversion."
            return 1
        fi
    fi

    cleanup_sra "$srr"
}

# -----------------------------------------------------------------------------
# step_fastqc <srr> <label> <file> [<file> ...]
# Runs FastQC on the supplied files. Non-fatal: pipeline continues on failure.
# -----------------------------------------------------------------------------
step_fastqc() {
    local srr="$1" label="$2"; shift 2
    log_step "$srr" "FASTQC_${label}" "Running FastQC ..."
    fastqc "$@" \
        --outdir  fastqc_out \
        --threads "$THREADS_FASTQC" \
        2>&1 | tee "${LOG_DIR}/${srr}_fastqc_${label,,}.log" || true
}

# -----------------------------------------------------------------------------
# step_multiqc_clean <srr> <layout>
# Runs MultiQC on the clean FastQC reports for this sample only.
# For PAIRED layout both forward (R1) and reverse (R2) reports are included,
# giving a side-by-side QC view of each strand. Output goes to multiqc_out/<srr>/.
# Non-fatal: pipeline continues on failure.
# -----------------------------------------------------------------------------
step_multiqc_clean() {
    local srr="$1" layout="$2"
    local mqc_out="multiqc_out/${srr}"
    mkdir -p "$mqc_out"

    if [[ "$layout" == "PAIRED" ]]; then
        local fwd_zip="fastqc_out/${srr}_1_clean_fastqc.zip"
        local rev_zip="fastqc_out/${srr}_2_clean_fastqc.zip"
        if [[ ! -f "$fwd_zip" || ! -f "$rev_zip" ]]; then
            log_step "$srr" "MULTIQC" "Clean FastQC outputs missing — skipping MultiQC."
            return 0
        fi
        log_step "$srr" "MULTIQC" "Running MultiQC on clean PE reads (R1 forward + R2 reverse) ..."
        multiqc "$fwd_zip" "$rev_zip" \
            --outdir   "$mqc_out" \
            --filename "${srr}_clean_multiqc" \
            2>&1 | tee "${LOG_DIR}/${srr}_multiqc_clean.log" || true
    else
        local se_zip="fastqc_out/${srr}_clean_fastqc.zip"
        if [[ ! -f "$se_zip" ]]; then
            log_step "$srr" "MULTIQC" "Clean FastQC output missing — skipping MultiQC."
            return 0
        fi
        log_step "$srr" "MULTIQC" "Running MultiQC on clean SE reads ..."
        multiqc "$se_zip" \
            --outdir   "$mqc_out" \
            --filename "${srr}_clean_multiqc" \
            2>&1 | tee "${LOG_DIR}/${srr}_multiqc_clean.log" || true
    fi
}

# -----------------------------------------------------------------------------
# step_bbduk <srr> <layout>
# Adapter-clips and quality-trims reads using bbduk.sh parameters from config.
# Deletes raw FASTQ on success.
# Populates globals CLEAN_1, CLEAN_2, CLEAN_S, SINGLETONS (PE only).
# -----------------------------------------------------------------------------
step_bbduk() {
    local srr="$1" layout="$2"
    CLEAN_1="clean_fastq/${srr}_1_clean.fastq.gz"
    CLEAN_2="clean_fastq/${srr}_2_clean.fastq.gz"
    SINGLETONS="clean_fastq/${srr}_singletons.fastq.gz"
    CLEAN_S="clean_fastq/${srr}_clean.fastq.gz"

    # Build parameter array from config values; omit any that are unset/empty.
    local bbduk_args=()
    [[ -n "${BBDUK_REF:-}"   ]] && bbduk_args+=( "ref=${BBDUK_REF}" )
    [[ -n "${BBDUK_KTRIM:-}" ]] && bbduk_args+=( "ktrim=${BBDUK_KTRIM}" )
    [[ -n "${BBDUK_K:-}"     ]] && bbduk_args+=( "k=${BBDUK_K}" )
    [[ -n "${BBDUK_MINK:-}"  ]] && bbduk_args+=( "mink=${BBDUK_MINK}" )
    [[ -n "${BBDUK_HDIST:-}" ]] && bbduk_args+=( "hdist=${BBDUK_HDIST}" )
    [[ -n "${BBDUK_QTRIM:-}" ]] && bbduk_args+=( "qtrim=${BBDUK_QTRIM}" )
    [[ -n "${BBDUK_TRIMQ:-}" ]] && bbduk_args+=( "trimq=${BBDUK_TRIMQ}" )
    [[ -n "${BBDUK_MINLEN:-}" ]] && bbduk_args+=( "minlen=${BBDUK_MINLEN}" )

    if [[ "$layout" == "PAIRED" ]]; then

        if [[ ! -f "$CLEAN_1" || ! -f "$CLEAN_2" ]]; then
            log_step "$srr" "BBDUK" "Trimming — PE mode ..."
            disk_usage "pre-bbduk [${srr}]"
            bbduk.sh \
                "in1=${RAW_1}"    "in2=${RAW_2}" \
                "out1=${CLEAN_1}" "out2=${CLEAN_2}" \
                "outs=${SINGLETONS}" \
                "t=${THREADS_TRIM}" \
                "${bbduk_args[@]}" \
                2>&1 | tee "${LOG_DIR}/${srr}_bbduk.log"
        else
            log_step "$srr" "BBDUK" "Clean PE FASTQ already present — skipping."
        fi

        if [[ ! -f "$CLEAN_1" || ! -f "$CLEAN_2" ]]; then
            log_step "$srr" "ERROR" "bbduk failed — clean PE FASTQ missing."
            cleanup_on_error "$srr" "$RAW_1" "$RAW_2" \
                "$CLEAN_1" "$CLEAN_2" "$SINGLETONS"
            return 1
        fi

        cleanup_raw_fastq "$srr" "$RAW_1" "$RAW_2"

    else

        if [[ ! -f "$CLEAN_S" ]]; then
            log_step "$srr" "BBDUK" "Trimming — SE mode ..."
            disk_usage "pre-bbduk [${srr}]"
            bbduk.sh \
                "in=${RAW_S}" \
                "out=${CLEAN_S}" \
                "t=${THREADS_TRIM}" \
                "${bbduk_args[@]}" \
                2>&1 | tee "${LOG_DIR}/${srr}_bbduk.log"
        else
            log_step "$srr" "BBDUK" "Clean SE FASTQ already present — skipping."
        fi

        if [[ ! -f "$CLEAN_S" ]]; then
            log_step "$srr" "ERROR" "bbduk failed — clean SE FASTQ missing."
            cleanup_on_error "$srr" "$RAW_S" "$CLEAN_S"
            return 1
        fi

        cleanup_raw_fastq "$srr" "$RAW_S"

    fi
}

# -----------------------------------------------------------------------------
# step_rsem <srr> <layout> <species_out>
# Runs STAR alignment then rsem-calculate-expression.
# Deletes clean FASTQ and BAM files on success.
# -----------------------------------------------------------------------------
step_rsem() {
    local srr="$1" layout="$2" species_out="$3"
    log_step "$srr" "STAR" "Aligning with STAR ..."
    disk_usage "pre-STAR [${srr}]"

    local star_out_prefix="${TMP_DIR}/${srr}_star/"
    mkdir -p "${TMP_DIR}/${srr}_star"

    # Determine decompression command: zcat for .gz inputs, cat for plain FASTQ
    # (plain FASTQ is produced when trimming is disabled).
    local rfcmd="cat"
    if [[ "$layout" == "PAIRED" ]]; then
        [[ "$CLEAN_1" == *.gz ]] && rfcmd="zcat"
    else
        [[ "$CLEAN_S" == *.gz ]] && rfcmd="zcat"
    fi

    local star_args=(
        --runThreadN              "$THREADS_STAR"
        --genomeDir               "$STAR_INDEX"
        --readFilesCommand        "$rfcmd"
        --outFileNamePrefix       "$star_out_prefix"
        --quantMode               TranscriptomeSAM
        --outSAMtype              BAM Unsorted
        --outSAMunmapped          Within
        --outFilterType           BySJout
        --outSAMattributes        NH HI AS NM MD
        --outFilterMultimapNmax   20
        --outFilterMismatchNmax   999
        --outFilterMismatchNoverReadLmax 0.04
        --alignIntronMin          20
        --alignIntronMax          1000000
        --alignMatesGapMax        1000000
        --alignSJoverhangMin      8
        --alignSJDBoverhangMin    1
        --sjdbScore               1
    )

    if [[ "$layout" == "PAIRED" ]]; then
        STAR "${star_args[@]}" \
            --readFilesIn "$CLEAN_1" "$CLEAN_2" \
            > "${LOG_DIR}/${srr}_star.log" 2>&1
    else
        STAR "${star_args[@]}" \
            --readFilesIn "$CLEAN_S" \
            > "${LOG_DIR}/${srr}_star.log" 2>&1
    fi

    if [[ ! -f "${star_out_prefix}Aligned.toTranscriptome.out.bam" ]]; then
        log_step "$srr" "ERROR" "STAR produced no transcriptome BAM — see ${LOG_DIR}/${srr}_star.log"
        rm -rf "${TMP_DIR}/${srr}_star"
        return 1
    fi

    log_step "$srr" "RSEM" "Quantifying with RSEM ..."
    disk_usage "pre-RSEM [${srr}]"

    if [[ "$layout" == "PAIRED" ]]; then
        rsem-calculate-expression \
            --paired-end \
            --alignments \
            --num-threads            "$THREADS_RSEM" \
            --temporary-folder       "${TMP_DIR}/${srr}_rsem_tmp" \
            "${star_out_prefix}Aligned.toTranscriptome.out.bam" \
            "$RSEM_REF" \
            "${species_out}/${srr}" \
            > "${LOG_DIR}/${srr}_rsem.log" 2>&1
    else
        rsem-calculate-expression \
            --alignments \
            --num-threads            "$THREADS_RSEM" \
            --temporary-folder       "${TMP_DIR}/${srr}_rsem_tmp" \
            "${star_out_prefix}Aligned.toTranscriptome.out.bam" \
            "$RSEM_REF" \
            "${species_out}/${srr}" \
            > "${LOG_DIR}/${srr}_rsem.log" 2>&1
    fi

    rm -rf "${TMP_DIR}/${srr}_star"
    cleanup_rsem_tmp "$srr"

    if [[ ! -f "${species_out}/${srr}.genes.results" ]]; then
        log_step "$srr" "ERROR" "genes.results missing — FASTQ retained for debugging. See ${LOG_DIR}/${srr}_rsem.log"
        return 1
    fi

    log_step "$srr" "SUCCESS" "genes.results confirmed → ${species_out}/${srr}.genes.results"

    if [[ "$layout" == "PAIRED" ]]; then
        cleanup_clean_fastq "$srr" "$CLEAN_1" "$CLEAN_2"
    else
        cleanup_clean_fastq "$srr" "$CLEAN_S"
    fi

    cleanup_rsem_bam "$srr" "$species_out"
}

# =============================================================================
# MAIN LOOP
# =============================================================================

echo "============================================================"
echo " 03_quantify.sh — Lepidoptera RNA-seq TPM pipeline"
echo " Samples  : ${SAMPLES_TSV}"
echo " Test     : ${TEST_MODE}"
echo "============================================================"

while IFS=$'\t' read -r SRR SPECIES LAYOUT; do

    [[ "$SRR" == "SRR" || -z "$SRR" ]] && continue

    echo ""
    echo "------------------------------------------------------------"
    echo " ${SRR}  |  ${SPECIES}  |  ${LAYOUT}"
    echo "------------------------------------------------------------"

    resolve_reference_paths "$SPECIES"

    SPECIES_OUT="rsem_results/${SPECIES}"
    mkdir -p "$SPECIES_OUT"

    if [[ -f "${SPECIES_OUT}/${SRR}.genes.results" ]]; then
        log_step "$SRR" "SKIP" "genes.results already exists — skipping."
        continue
    fi

    step_prefetch      "$SRR"           || continue
    step_fasterq_dump  "$SRR" "$LAYOUT" || continue

    if [[ "$LAYOUT" == "PAIRED" ]]; then
        step_fastqc "$SRR" "RAW" "$RAW_1" "$RAW_2"
    else
        step_fastqc "$SRR" "RAW" "$RAW_S"
    fi

    if [[ "${TRIMMING_ENABLED:-true}" == "true" ]]; then
        step_bbduk "$SRR" "$LAYOUT" || continue
        if [[ "$LAYOUT" == "PAIRED" ]]; then
            step_fastqc "$SRR" "CLEAN" "$CLEAN_1" "$CLEAN_2"
            step_multiqc_clean "$SRR" "PAIRED"
            cleanup_unpaired_fastq "$SRR" "$SINGLETONS"
        else
            step_fastqc "$SRR" "CLEAN" "$CLEAN_S"
            step_multiqc_clean "$SRR" "SINGLE"
        fi
    else
        log_step "$SRR" "TRIM" "Trimming disabled — routing raw FASTQ directly to STAR/RSEM."
        if [[ "$LAYOUT" == "PAIRED" ]]; then
            CLEAN_1="$RAW_1"
            CLEAN_2="$RAW_2"
        else
            CLEAN_S="$RAW_S"
        fi
    fi

    step_rsem "$SRR" "$LAYOUT" "$SPECIES_OUT" || continue

    log_step "$SRR" "DONE" "Sample complete."
    disk_usage "post-sample [${SRR}]"

done < "$SAMPLES_TSV"

echo ""
echo "============================================================"
echo ""
echo " All samples processed."
echo ""
echo "============================================================"
