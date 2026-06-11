# Lepidoptera Catalytic Triad — RNA-seq TPM Pipeline

Modular, reproducible pipeline for TPM quantification across six Lepidoptera
species with contrasting feeding breadth. Targets midgut transcriptomes from
larval and adult stages to support the identification of the serine protease
catalytic triad.

**Methodology:**
**Institution:** Laboratorio —  Universidade de Nariño
**PI:** Zambrano Leiton Juan Sebastian

---

## Target species

| Feeding type | Species                   | Key in pipeline            |
|:-------------|:--------------------------|:---------------------------|
| Polyphagous  | *Spodoptera frugiperda*   | `Spodoptera_frugiperda`    |
| Polyphagous  | *Plutella xylostella*     | `Plutella_xylostella`      |
| Polyphagous  | *Diatraea saccharalis*    | `Diatraea_saccharalis`     |
| Monophagous  | *Bombyx mori*             | `Bombyx_mori`              |
| Monophagous  | *Tecia solanivora*        | `Tecia_solanivora`         |
| Monophagous  | *Cactoblastis cactorum*   | `Cactoblastis_cactorum`    |

GTF — = no annotation available; reference-building is skipped for that species (genome FASTA is still downloaded).

---

## Repository structure

```
.
├── config.sh                    # All user-editable parameters (sourced by every module)
├── 00_setup.sh                  # Interactive compute-resource and trimming configurator
├── 01_build_references.sh       # Download genomes + build STAR/RSEM indexes
├── 02_prepare_samples.py        # Parse SRA RunTable → samples.tsv
├── 03_quantify.sh               # Main per-sample quantification loop
├── lib/
│   ├── utils.sh                 # Logging, tool checks, disk monitoring
│   └── cleanup.sh               # Per-step intermediate file deletion
├── environment.yml              # Conda environment specification
├── .gitignore
└── README.md
```

---

## Software requirements

All tools are pinned in `environment.yml`. Install with:

```bash
conda env create -f environment.yml
conda activate lepidoptera-rnaseq
```

| Tool            | Version | Role                                  |
|:----------------|:--------|:--------------------------------------|
| SRA-Toolkit     | 3.0.0   | `prefetch`, `fasterq-dump`            |
| FastQC          | 0.12    | Per-sample quality control            |
| MultiQC         | 1.14    | Aggregated QC report                  |
| BBMap (bbduk.sh)| ≥ 39    | Adapter removal, quality trimming (optional) |
| STAR            | 2.7.10  | Splice-aware alignment (via RSEM)     |
| RSEM            | 1.3.3   | TPM/FPKM quantification               |
| Python          | ≥ 3.9   | `02_prepare_samples.py`               |
| openpyxl        | ≥ 3.0   | SRA RunTable parsing                  |

---

## Execution — step by step

### Step 0 — Configure compute resources

```bash
bash 00_setup.sh
```

Detects available CPUs and disk space; prompts for thread counts, storage
limits, and trimming settings (enable/disable bbduk and key quality parameters);
writes the values to `config.sh`. Re-run whenever resources change.
Alternatively, edit `config.sh` directly.

### Step 1 — Build genome references *(run once)*

```bash
bash 01_build_references.sh
```

Downloads genome FASTA and GTF from NCBI RefSeq for each species, builds the
STAR genome index, and prepares the RSEM reference. Skips any species whose
index already exists. Species configured with `NO_GTF` are skipped with a
warning and do not cause the script to abort.

> **Disk estimate:** ~2–4 GB per species for indexes; genome FASTA and GTF
> are kept for potential re-indexing.

### Step 2 — Prepare the sample list

```bash
python3 02_prepare_samples.py --input SraRunTable.xlsx
```

Parses the NCBI SRA RunTable, filters for RNA-Seq TRANSCRIPTOMIC gut/midgut
samples from the six target species, and writes `samples.tsv` (three columns:
`SRR`, `SPECIES`, `LAYOUT`). Review this file before proceeding.

Optional flags:

| Flag | Effect |
|:-----|:-------|
| `--all-tissues` | Disable gut/midgut filter — keep all tissues |
| `--include-species X Y` | Restrict output to specific species keys |
| `--output path/to/file.tsv` | Custom output path (default: `samples.tsv`) |

### Step 3 — Run the quantification loop

```bash
# Full run
bash 03_quantify.sh

# Test run — limits fasterq-dump to 500 000 reads per sample
bash 03_quantify.sh --test
```

Per-sample steps:

```
prefetch → fasterq-dump → FastQC (raw)
    → bbduk.sh* → FastQC (clean) → MultiQC (clean)
    → STAR + RSEM → cleanup
```

\* bbduk trimming is optional; set `TRIMMING_ENABLED=false` in `config.sh` to
skip it and route raw FASTQ directly to STAR/RSEM (post-trim QC steps are also
skipped).

The loop is **idempotent**: if `rsem_results/<species>/<SRR>.genes.results`
already exists, that sample is skipped. Interrupted runs resume from where
they stopped.

---

## Output files

```
rsem_results/
└── <species>/
    ├── <SRR>.genes.results       ← TPM, FPKM, expected_count (gene level)
    └── <SRR>.isoforms.results    ← TPM, FPKM, expected_count (isoform level)
fastqc_out/                       ← Per-sample FastQC HTML + ZIP reports
multiqc_out/                      ← Aggregated MultiQC HTML report
logs/                             ← Per-sample and per-step logs
```

The `TPM` column in `*.genes.results` is the primary value for downstream
comparative analyses.

---

## Disk management

Intermediate files are deleted immediately after each step confirms its output:

| Function (lib/cleanup.sh) | Files deleted | Freed per sample |
|:--------------------------|:--------------|:-----------------|
| `cleanup_sra` | `.sra` + prefetch dir | 1–5 GB |
| `cleanup_raw_fastq` | Uncompressed raw FASTQ | 2–10 GB |
| `cleanup_unpaired_fastq` | bbduk PE singleton reads | 0.2–1 GB |
| `cleanup_clean_fastq` | Trimmed `.fastq.gz` (or raw FASTQ when trimming is disabled) | 1–4 GB |
| `cleanup_rsem_bam` | `.transcript.bam`, `.genome.bam` | 10–60 GB |
| `cleanup_rsem_tmp` | RSEM/STAR temp directory | variable |
| `cleanup_on_error` | All partial outputs on failure | prevents stale locks |

`lib/utils.sh::disk_usage` logs free space before and after each step and
emits a non-fatal warning when available space drops below `DISK_WARN_GB`
(default 20 GB, configurable in `config.sh`).

---

## Testing

Use `--test` mode to validate the pipeline before a full run. It limits
`fasterq-dump` to 500 000 reads per sample, so the entire loop completes
in minutes on a single test accession:

```bash
bash 03_quantify.sh --test
```

Confirm the output: `rsem_results/<species>/<SRR>.genes.results` should exist
and contain non-zero TPM values. Check `logs/<SRR>.log` for per-step timing
and `logs/<SRR>_bbduk.log` (when trimming is enabled) for adapter-removal
statistics.

---

## References

- Andrews, S. (2010). *FastQC*. https://www.bioinformatics.babraham.ac.uk/projects/fastqc/
- Bushnell, B. BBMap/BBDuk. https://sourceforge.net/projects/bbmap/
- Dobin, A. et al. (2013). STAR. *Bioinformatics*, 29(1), 15–21.
- Li, B. & Dewey, C. N. (2011). RSEM. *BMC Bioinformatics*, 12, 323.
- Matabanchoi & Mayama (2023). *(update full citation before publication)*
- NCBI SRA Toolkit. https://github.com/ncbi/sra-tools
- Sewe, S. O. et al. (2022). *(update full citation before publication)*
