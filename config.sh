#!/usr/bin/env bash
# config.sh — Runtime configuration for the Lepidoptera RNA-seq TPM pipeline.
# All other modules source this file; edit only this file before each run.

# =============================================================================
# COMPUTE RESOURCES
# Set interactively at runtime by running:  bash pipeline.sh --setup
# or edit the values below manually before running.
# =============================================================================
THREADS_DOWNLOAD=28
THREADS_FASTQC=28
THREADS_TRIM=28
THREADS_STAR=30
THREADS_RSEM=30
MAX_SRA_SIZE="200G"

# =============================================================================
# PATHS
# =============================================================================
REFERENCES_DIR="references"
SAMPLES_TSV="samples.tsv"
LOG_DIR="logs"
TMP_DIR="tmp"

# =============================================================================
# TRIMMING
# Set TRIMMING_ENABLED=false to route raw FASTQ directly into STAR/RSEM.
# All bbduk.sh parameters below are ignored when trimming is disabled.
# =============================================================================
TRIMMING_ENABLED=true
TRIMMER="bbduk"

# Adapter reference — "adapters" resolves to bbduk's built-in library.
# Override with an absolute path to a custom adapter FASTA if needed.
BBDUK_REF="adapters"

# Adapter trimming parameters (k-mer based, right-end trim).
BBDUK_KTRIM="r"
BBDUK_K=23
BBDUK_MINK=11
BBDUK_HDIST=1

# Quality trimming: trim both ends; discard reads shorter than BBDUK_MINLEN.
BBDUK_QTRIM="rl"
BBDUK_TRIMQ=20
BBDUK_MINLEN=36

# STAR sjdbOverhang = read_length - 1. Default assumes 150 bp reads.
STAR_OVERHANG=149

# genomeSAindexNbases for Lepidoptera genomes (~300–500 Mb).
# Formula: min(14, floor(log2(genome_size) / 2 - 1))
STAR_SA_INDEX_NBASES=13

# =============================================================================
# STORAGE MONITORING
# Warn (non-fatal) when free disk space drops below this threshold (GB).
# =============================================================================
DISK_WARN_GB=20

# =============================================================================
# SPECIES REFERENCE TABLE
# Format: "species_key|genome_fna_gz_url|genome_gtf_gz_url"
# species_key must match the subdirectory name under $REFERENCES_DIR.
# URLs verified against NCBI RefSeq/GenBank — 2026-05.
# =============================================================================
declare -a SPECIES_CONFIG=(

    # -- Polyphagous ----------------------------------------------------------
    "Spodoptera_frugiperda|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/023/101/765/GCF_023101765.2_AGI-APGP_CSIRO_Sfru_2.0/GCF_023101765.2_AGI-APGP_CSIRO_Sfru_2.0_genomic.fna.gz|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/023/101/765/GCF_023101765.2_AGI-APGP_CSIRO_Sfru_2.0/GCF_023101765.2_AGI-APGP_CSIRO_Sfru_2.0_genomic.gtf.gz|\
true"

    "Plutella_xylostella|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/932/276/165/GCF_932276165.2_ilPluXylo3.2/GCF_932276165.2_ilPluXylo3.2_genomic.fna.gz|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/932/276/165/GCF_932276165.2_ilPluXylo3.2/GCF_932276165.2_ilPluXylo3.2_genomic.gtf.gz|\
true"

    "Diatraea_saccharalis|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/918/026/875/GCA_918026875.4_PGI_DIATSA_v4/GCA_918026875.4_PGI_DIATSA_v4_genomic.fna.gz|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/918/026/875/GCA_918026875.4_PGI_DIATSA_v4/GCA_918026875.4_PGI_DIATSA_v4_genomic.gtf.gz|\
true"

    # -- Monophagous ----------------------------------------------------------
    "Bombyx_mori|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/030/269/925/GCF_030269925.1_ASM3026992v2/GCF_030269925.1_ASM3026992v2_genomic.fna.gz|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/030/269/925/GCF_030269925.1_ASM3026992v2/GCF_030269925.1_ASM3026992v2_genomic.gtf.gz|\
true"

    "Tecia_solanivora|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/045/412/185/GCA_045412185.1_GL_inrae_Tsol_v2/GCA_045412185.1_GL_inrae_Tsol_v2_genomic.fna.gz|\
NO_GTF|\
false"
    "Cactoblastis_cactorum|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/020/352/625/GCA_020352625.1_CactoFuEDEI/GCA_020352625.1_CactoFuEDEI_genomic.fna.gz|\
NO_GTF|\
false"

    #"Phyllocnistis_citrella|\

    # -- test species ----------------------------------------------------------
    "Helicoverpa_armigera|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/030/705/265/GCF_030705265.1_ASM3070526v1/GCF_030705265.1_ASM3070526v1_genomic.fna.gz|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/030/705/265/GCF_030705265.1_ASM3070526v1/GCF_030705265.1_ASM3070526v1_genomic.gtf.gz|\
true"
)
