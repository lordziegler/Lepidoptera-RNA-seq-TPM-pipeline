#!/usr/bin/env bash
# lib/cleanup.sh — Per-step disk-cleanup functions.
# Each function targets one file category and is called the moment its
# files are no longer needed, keeping peak disk usage minimal.

# -----------------------------------------------------------------------------
# cleanup_sra <srr>
# -----------------------------------------------------------------------------
cleanup_sra() {
    local srr="$1"
    log_step "$srr" "CLEANUP" "Removing .sra — FASTQ conversion confirmed."
    rm -f  "sra/${srr}/${srr}.sra" "sra/${srr}.sra"
    rm -rf "sra/${srr}"
    disk_usage "post-SRA-cleanup [${srr}]"
}

# -----------------------------------------------------------------------------
# cleanup_raw_fastq <srr> <file> [<file> ...]
# -----------------------------------------------------------------------------
cleanup_raw_fastq() {
    local srr="$1"; shift
    log_step "$srr" "CLEANUP" "Removing raw FASTQ — trimmed files confirmed."
    rm -f "$@"
    disk_usage "post-raw-fastq-cleanup [${srr}]"
}

# -----------------------------------------------------------------------------
# cleanup_unpaired_fastq <srr> <file> [<file> ...]
# -----------------------------------------------------------------------------
cleanup_unpaired_fastq() {
    local srr="$1"; shift
    log_step "$srr" "CLEANUP" "Removing PE unpaired FASTQ — not used downstream."
    rm -f "$@"
    disk_usage "post-unpaired-cleanup [${srr}]"
}

# -----------------------------------------------------------------------------
# cleanup_clean_fastq <srr> <file> [<file> ...]
# -----------------------------------------------------------------------------
cleanup_clean_fastq() {
    local srr="$1"; shift
    log_step "$srr" "CLEANUP" "Removing clean FASTQ — RSEM output confirmed."
    rm -f "$@"
    disk_usage "post-clean-fastq-cleanup [${srr}]"
}

# -----------------------------------------------------------------------------
# cleanup_rsem_bam <srr> <species_out_dir>
# -----------------------------------------------------------------------------
cleanup_rsem_bam() {
    local srr="$1" species_out="$2"
    log_step "$srr" "CLEANUP" "Removing RSEM BAM files — genes.results confirmed."
    rm -f "${species_out}/${srr}.transcript.bam"
    rm -f "${species_out}/${srr}.genome.bam"
    rm -f "${species_out}/${srr}.STAR.genome.bam"
    disk_usage "post-BAM-cleanup [${srr}]"
}

# -----------------------------------------------------------------------------
# cleanup_rsem_tmp <srr>
# -----------------------------------------------------------------------------
cleanup_rsem_tmp() {
    local srr="$1"
    log_step "$srr" "CLEANUP" "Removing RSEM temporary directory."
    rm -rf "${TMP_DIR}/${srr}_rsem_tmp"
    disk_usage "post-tmp-cleanup [${srr}]"
}

# -----------------------------------------------------------------------------
# cleanup_on_error <srr> <file> [<file> ...]
# -----------------------------------------------------------------------------
cleanup_on_error() {
    local srr="$1"; shift
    log_step "$srr" "CLEANUP" "Removing partial files after failure."
    rm -f "$@"
    rm -rf "${TMP_DIR}/${srr}_rsem_tmp"
    disk_usage "post-error-cleanup [${srr}]"
}
