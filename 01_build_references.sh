#!/usr/bin/env bash
# 01_build_references.sh — Downloads genome FASTA and GTF from NCBI RefSeq
# and builds STAR genome index + RSEM reference for each target species.
# Must be executed once before 03_quantify.sh.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/lib/utils.sh"

mkdir -p "$LOG_DIR"

# -----------------------------------------------------------------------------
# download_and_decompress <gz_url> <gz_out> <final_out>
# Downloads a gzipped file, decompresses it, and removes the archive
# immediately to conserve disk space.
# -----------------------------------------------------------------------------
download_and_decompress() {
    local url="$1" gz_out="$2" final_out="$3"
    if [[ -f "$final_out" ]]; then
        echo "[SKIP] Already exists: ${final_out}"
        return 0
    fi
    echo "[DOWNLOAD] ${url##*/}"
    wget -q --show-progress -O "$gz_out" "$url"
    gunzip -c "$gz_out" > "$final_out"
    rm -f "$gz_out"
    disk_usage "post-download [${final_out##*/}]"
}

# -----------------------------------------------------------------------------
# build_species_reference <entry>
# Parses one SPECIES_CONFIG entry, downloads genome + GTF, builds the
# STAR index and RSEM reference. Idempotent: skips if both indexes exist.
# -----------------------------------------------------------------------------
build_species_reference() {
    local entry="$1"
    local species fna_url gtf_url is_active
    IFS='|' read -r species fna_url gtf_url is_active <<< "$entry"

    local sp_dir="${REFERENCES_DIR}/${species}"
    local star_idx="${sp_dir}/STAR_genome_index"
    local rsem_ref="${sp_dir}/rsem_ref"
    local genome_fa="${sp_dir}/genome.fa"
    local genes_gtf="${sp_dir}/genes.gtf"

    if [[ "${is_active,,}" == "false" ]]; then
        echo "[SKIP] ${species} is marked as false in config.sh"
        return 0
    fi

    if [[ "$gtf_url" == "NO_GTF" || -z "$gtf_url" ]]; then
        echo "[WARN] ${species} — no GTF annotation configured. Skipping reference build."
        return 0
    fi

    echo ""
    echo "------------------------------------------------------------"
    echo " Species: ${species}"
    echo "------------------------------------------------------------"

    mkdir -p "$sp_dir" "$star_idx"

    if [[ -f "${rsem_ref}.grp" && -f "${star_idx}/SA" ]]; then
        echo "[SKIP] References already built for ${species}."
        return 0
    fi

    download_and_decompress "$fna_url" "${sp_dir}/genome.fna.gz" "$genome_fa"
    download_and_decompress "$gtf_url" "${sp_dir}/genes.gtf.gz"  "$genes_gtf"

    echo "[STAR] Building genome index for ${species} ..."
    STAR \
        --runThreadN          "$THREADS_STAR" \
        --runMode             genomeGenerate \
        --genomeDir           "$star_idx" \
        --genomeFastaFiles    "$genome_fa" \
        --sjdbGTFfile         "$genes_gtf" \
        --sjdbOverhang        "$STAR_OVERHANG" \
        --genomeSAindexNbases "$STAR_SA_INDEX_NBASES" \
        2>&1 | tee "${sp_dir}/star_index.log"

    echo "[RSEM] Preparing reference for ${species} ..."
    rsem-prepare-reference \
        --gtf      "$genes_gtf" \
        "$genome_fa" \
        "$rsem_ref" \
        2>&1 | tee "${sp_dir}/rsem_prepare.log"

    disk_usage "post-index [${species}]"
    echo "[DONE] ${species}"
}

# --- Pre-flight --------------------------------------------------------------
for tool in wget STAR rsem-prepare-reference; do check_tool "$tool"; done

echo "============================================================"
echo " Building genome references for all target species"
echo "============================================================"
mkdir -p "$REFERENCES_DIR"

for entry in "${SPECIES_CONFIG[@]}"; do
    build_species_reference "$entry" || \
        echo "[ERROR] Reference build failed for ${entry%%|*} — continuing with next species."
done

echo ""
echo "============================================================"
echo " All references built."
echo " Next: python3 02_prepare_samples.py --input <RunTable.xlsx>"
echo "============================================================"
