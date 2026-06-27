#!/usr/bin/env bash
# Converts an SRA archive to FASTQ.
# On success sets globals: RAW_1, RAW_2, RAW_SE

step_fastq_dump() {
    local srr="$1" layout="$2"

    RAW_1="fastq/${srr}_1.fastq"
    RAW_2="fastq/${srr}_2.fastq"
    RAW_SE="fastq/${srr}.fastq"

    local already_done=false
    [[ "$layout" == "PAIRED" && -f "$RAW_1" && -f "$RAW_2" ]] && already_done=true
    [[ "$layout" == "SINGLE" && -f "$RAW_SE" ]]               && already_done=true

    if [[ "$already_done" == false ]]; then
        if [[ "$TEST_MODE" == true ]]; then
            log_step "$srr" "FASTQ-DUMP" "Test mode: ${TEST_READS} reads (${layout}) ..."
            fastq-dump "$SRA_PATH" \
                --outdir fastq \
                --split-3 \
                -X "$TEST_READS" \
                2>&1 | tee "${LOG_DIR}/${srr}_fastq_dump.log"
        else
            log_step "$srr" "FASTERQ-DUMP" "Extracting all reads (${layout}) ..."
            fasterq-dump "$SRA_PATH" \
                --outdir  fastq \
                --temp    "$TMP_DIR" \
                --split-3 \
                --threads "$THREADS_DOWNLOAD" \
                2>&1 | tee "${LOG_DIR}/${srr}_fasterq.log"
        fi
    else
        log_step "$srr" "FASTQ" "Raw FASTQ already present — skipping."
    fi

    if [[ "$layout" == "PAIRED" ]]; then
        if [[ ! -f "$RAW_1" || ! -f "$RAW_2" ]]; then
            log_step "$srr" "ERROR" "Paired FASTQ missing after extraction."
            return 1
        fi
    else
        if [[ ! -f "$RAW_SE" ]]; then
            log_step "$srr" "ERROR" "Single-end FASTQ missing after extraction."
            return 1
        fi
    fi
}
