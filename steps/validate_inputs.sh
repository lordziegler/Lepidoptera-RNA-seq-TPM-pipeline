#!/usr/bin/env bash
# Locates exactly one genome FASTA, one GTF, and one SRA RunTable
# in the given directory. Sets globals: FNA_FILE, GTF_FILE, RUN_TABLE.

detect_inputs() {
    local search_dir="${1:-.}"
    local errors=0

    mapfile -t _fna < <(find "$search_dir" -maxdepth 1 -type f \
        \( -name "*.fna.gz" -o -name "*.fa.gz" -o -name "*.fasta.gz" \) | sort)
    mapfile -t _gtf < <(find "$search_dir" -maxdepth 1 -type f \
        -name "*.gtf.gz" | sort)
    mapfile -t _tbl < <(find "$search_dir" -maxdepth 1 -type f \
        \( -iname "*SraRunTable*.csv" -o -iname "*RunTable*.csv" \
           -o -iname "*SraRunTable*.xlsx" -o -iname "*RunTable*.xlsx" \) | sort)

    if [[ ${#_fna[@]} -ne 1 ]]; then
        echo "[ERROR] Expected 1 genome FASTA (.fna.gz/.fa.gz/.fasta.gz), found ${#_fna[@]}."
        (( errors++ )) || true
    fi
    if [[ ${#_gtf[@]} -ne 1 ]]; then
        echo "[ERROR] Expected 1 GTF (.gtf.gz), found ${#_gtf[@]}."
        (( errors++ )) || true
    fi
    if [[ ${#_tbl[@]} -ne 1 ]]; then
        echo "[ERROR] Expected 1 SRA RunTable (.csv/.xlsx), found ${#_tbl[@]}."
        (( errors++ )) || true
    fi

    if [[ "$errors" -gt 0 ]]; then
        echo "[ABORT] Input validation failed (${errors} error(s))."
        exit 1
    fi

    FNA_FILE="${_fna[0]}"
    GTF_FILE="${_gtf[0]}"
    RUN_TABLE="${_tbl[0]}"

    echo "[OK] FASTA    : ${FNA_FILE}"
    echo "[OK] GTF      : ${GTF_FILE}"
    echo "[OK] RunTable : ${RUN_TABLE}"
}
