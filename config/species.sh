#!/usr/bin/env bash
# Species reference table.
# Format per entry: "name|fna_url|gtf_url|active"
# Set active=false to skip a species without removing the entry.

declare -a SPECIES_CONFIG=(

    "Helicoverpa_armigera|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/030/705/265/GCF_030705265.1_ASM3070526v1/GCF_030705265.1_ASM3070526v1_genomic.fna.gz|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/030/705/265/GCF_030705265.1_ASM3070526v1/GCF_030705265.1_ASM3070526v1_genomic.gtf.gz|\
true"

    "Spodoptera_frugiperda|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/023/101/765/GCF_023101765.2_AGI-APGP_CSIRO_Sfru_2.0/GCF_023101765.2_AGI-APGP_CSIRO_Sfru_2.0_genomic.fna.gz|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/023/101/765/GCF_023101765.2_AGI-APGP_CSIRO_Sfru_2.0/GCF_023101765.2_AGI-APGP_CSIRO_Sfru_2.0_genomic.gtf.gz|\
true"

    "Plutella_xylostella|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/932/276/165/GCF_932276165.2_ilPluXylo3.2/GCF_932276165.2_ilPluXylo3.2_genomic.fna.gz|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/932/276/165/GCF_932276165.2_ilPluXylo3.2/GCF_932276165.2_ilPluXylo3.2_genomic.gtf.gz|\
true"

    "Bombyx_mori|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/030/269/925/GCF_030269925.1_ASM3026992v2/GCF_030269925.1_ASM3026992v2_genomic.fna.gz|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/030/269/925/GCF_030269925.1_ASM3026992v2/GCF_030269925.1_ASM3026992v2_genomic.gtf.gz|\
false"

    "Diatraea_saccharalis|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/918/026/875/GCA_918026875.4_PGI_DIATSA_v4/GCA_918026875.4_PGI_DIATSA_v4_genomic.fna.gz|\
https://ftp.ncbi.nlm.nih.gov/genomes/all/GCA/918/026/875/GCA_918026875.4_PGI_DIATSA_v4/GCA_918026875.4_PGI_DIATSA_v4_genomic.gtf.gz|\
false"
)
