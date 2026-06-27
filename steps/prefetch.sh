#!/usr/bin/env bash
# Downloads an SRA archive with configurable retry.
# On success sets global: SRA_PATH

step_prefetch() {
    local srr="$1"
    local sra_a="sra/${srr}/${srr}.sra"
    local sra_b="sra/${srr}.sra"

    if [[ -f "$sra_a" ]]; then SRA_PATH="$sra_a"; log_step "$srr" "PREFETCH" "Already present."; return 0; fi
    if [[ -f "$sra_b" ]]; then SRA_PATH="$sra_b"; log_step "$srr" "PREFETCH" "Already present."; return 0; fi

    local attempt=1
    while [[ "$attempt" -le "$PREFETCH_RETRIES" ]]; do
        log_step "$srr" "PREFETCH" "Attempt ${attempt}/${PREFETCH_RETRIES} ..."

        prefetch "$srr" \
            --output-directory sra \
            --max-size "$MAX_SRA_SIZE" \
            2>&1 | tee "${LOG_DIR}/${srr}_prefetch_${attempt}.log"

        if   [[ -f "$sra_a" ]]; then SRA_PATH="$sra_a"; log_step "$srr" "PREFETCH" "Done."; return 0
        elif [[ -f "$sra_b" ]]; then SRA_PATH="$sra_b"; log_step "$srr" "PREFETCH" "Done."; return 0
        fi

        log_step "$srr" "PREFETCH" "Attempt ${attempt} failed."
        rm -f "$sra_a" "$sra_b"; rmdir "sra/${srr}" 2>/dev/null || true

        if [[ "$attempt" -lt "$PREFETCH_RETRIES" ]]; then
            log_step "$srr" "PREFETCH" "Waiting ${PREFETCH_RETRY_SLEEP}s ..."
            sleep "$PREFETCH_RETRY_SLEEP"
        fi
        (( attempt++ ))
    done

    log_step "$srr" "ERROR" "prefetch failed after ${PREFETCH_RETRIES} attempts."
    return 1
}
