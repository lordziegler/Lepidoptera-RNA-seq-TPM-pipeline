#!/usr/bin/env bash
# Quality trimming with BBDuk.
# On success sets globals: CLEAN_1, CLEAN_2, CLEAN_SE (and SINGLETONS for PE).

_bbduk_args() {
    local args=()
    [[ -n "${BBDUK_REF:-}"   ]] && args+=("ref=${BBDUK_REF}")
    [[ -n "${BBDUK_KTRIM:-}" ]] && args+=("ktrim=${BBDUK_KTRIM}")
    [[ -n "${BBDUK_K:-}"     ]] && args+=("k=${BBDUK_K}")
    [[ -n "${BBDUK_MINK:-}"  ]] && args+=("mink=${BBDUK_MINK}")
    [[ -n "${BBDUK_HDIST:-}" ]] && args+=("hdist=${BBDUK_HDIST}")
    args+=("qtrim=${BBDUK_QTRIM}" "trimq=${BBDUK_TRIMQ}" "minlen=${BBDUK_MINLEN}")
    echo "${args[@]}"
}

step_bbduk() {
    local srr="$1" layout="$2"

    CLEAN_1="clean_fastq/${srr}_1_clean.fastq.gz"
    CLEAN_2="clean_fastq/${srr}_2_clean.fastq.gz"
    SINGLETONS="clean_fastq/${srr}_singletons.fastq.gz"
    CLEAN_SE="clean_fastq/${srr}_clean.fastq.gz"

    mkdir -p clean_fastq
    read -ra _args <<< "$(_bbduk_args)"

    if [[ "$layout" == "PAIRED" ]]; then
        if [[ ! -f "$CLEAN_1" || ! -f "$CLEAN_2" ]]; then
            log_step "$srr" "BBDUK" "Trimming PE reads ..."
            bbduk.sh \
                "in1=${RAW_1}" "in2=${RAW_2}" \
                "out1=${CLEAN_1}" "out2=${CLEAN_2}" "outs=${SINGLETONS}" \
                "t=${THREADS_TRIM}" \
                "${_args[@]}" \
                2>&1 | tee "${LOG_DIR}/${srr}_bbduk.log"
        else
            log_step "$srr" "BBDUK" "Clean PE FASTQ already present — skipping."
        fi
        if [[ ! -f "$CLEAN_1" || ! -f "$CLEAN_2" ]]; then
            log_step "$srr" "ERROR" "BBDuk failed — clean paired FASTQ missing."
            return 1
        fi

    else
        if [[ ! -f "$CLEAN_SE" ]]; then
            log_step "$srr" "BBDUK" "Trimming SE reads ..."
            bbduk.sh \
                "in=${RAW_SE}" "out=${CLEAN_SE}" \
                "t=${THREADS_TRIM}" \
                "${_args[@]}" \
                2>&1 | tee "${LOG_DIR}/${srr}_bbduk.log"
        else
            log_step "$srr" "BBDUK" "Clean SE FASTQ already present — skipping."
        fi
        if [[ ! -f "$CLEAN_SE" ]]; then
            log_step "$srr" "ERROR" "BBDuk failed — clean single-end FASTQ missing."
            return 1
        fi
    fi
}
