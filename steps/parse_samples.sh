#!/usr/bin/env bash
# Calls the Python helper to parse the SRA RunTable and write samples.tsv.

parse_samples() {
    echo "[INFO] Parsing RunTable: ${RUN_TABLE}"
    mkdir -p "$(dirname "$SAMPLES_TSV")"

    python3 "${PIPELINE_DIR}/helpers/parse_runtable.py" \
        --input  "$RUN_TABLE" \
        --output "$SAMPLES_TSV"

    require_file "$SAMPLES_TSV" "parse_runtable.py failed to produce samples.tsv."
    echo "[DONE] samples.tsv: ${SAMPLES_TSV}"
}
