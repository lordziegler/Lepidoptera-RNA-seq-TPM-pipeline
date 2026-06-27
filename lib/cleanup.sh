#!/usr/bin/env bash
# Per-step disk cleanup functions.
# Each function is called immediately after its files are no longer needed.

cleanup_sra() {
    local srr="$1" sra_path="$2"
    rm -f "$sra_path"
    rmdir "sra/${srr}" 2>/dev/null || true
    log_step "$srr" "CLEANUP" "SRA removed."
    disk_usage "post-sra-cleanup [${srr}]"
}

cleanup_raw_fastq() {
    local srr="$1"; shift
    rm -f "$@"
    log_step "$srr" "CLEANUP" "Raw FASTQ removed."
}

cleanup_clean_fastq() {
    local srr="$1"; shift
    rm -f "$@"
    log_step "$srr" "CLEANUP" "Clean FASTQ removed."
}

cleanup_star_tmp() {
    local srr="$1"
    rm -rf "${TMP_DIR}/${srr}_star"
    log_step "$srr" "CLEANUP" "STAR temp dir removed."
    disk_usage "post-star-cleanup [${srr}]"
}

cleanup_rsem_bam() {
    local srr="$1" species_out="$2"
    rm -f "${species_out}/${srr}.transcript.bam" \
          "${species_out}/${srr}.genome.bam" \
          "${species_out}/${srr}.STAR.genome.bam"
    log_step "$srr" "CLEANUP" "RSEM BAM files removed."
    disk_usage "post-bam-cleanup [${srr}]"
}

cleanup_rsem_tmp() {
    local srr="$1"
    rm -rf "${TMP_DIR}/${srr}_rsem_tmp"
}

cleanup_on_error() {
    local srr="$1"; shift
    rm -f "$@"
    rm -rf "${TMP_DIR}/${srr}_rsem_tmp" "${TMP_DIR}/${srr}_star"
    log_step "$srr" "CLEANUP" "Partial files removed after failure."
}
