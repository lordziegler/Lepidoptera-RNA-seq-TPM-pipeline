# Release Notes — Lepidoptera RNA-seq TPM Pipeline

---

## v2.0.0 — 2026-06-26 — Full modular refactor

### Summary

Complete rewrite from the original script-based pipeline (`03_quantify.sh`).
Embedded Python heredocs were extracted into standalone helpers, the trimmer
was unified to BBDuk, an atomic sample tracker and a functional retry loop
were added, and a unit test suite was introduced.

---

### What's new

**Architecture**
- Pipeline reorganised into `config/`, `lib/`, `steps/`, `helpers/`, and `tests/`.
  19 files; single entry point: `bash run.sh`.
- Each analysis stage has its own file under `steps/`:
  `validate_inputs`, `build_references`, `parse_samples`, `prefetch`,
  `fastq_dump`, `fastqc`, `trim`, `align`, `quantify`, `postprocess`.

**Configuration**
- `config/species.sh`: multi-species array with an `active` flag (true/false).
  Adding or disabling a species requires no code changes.
- `config/pipeline.sh`: all runtime variables in a single file with no
  duplicated values across modules.

**Standalone Python helpers**
- `helpers/parse_runtable.py`: `argparse` CLI; accepts `.csv` and `.xlsx`;
  replaces the inline Python block from the v1 pipeline.
- `helpers/build_matrix.py`: produces `gene_expression_matrix.tsv` (inner join
  of all `genes.results`), `STAR_mapping_QC_matrix.tsv`, and
  `BBDUK_preprocessing_QC_matrix.tsv`.

**Sample tracker**
- `lib/sample_tracker.sh`: `pipeline_sample_summary.tsv` with 11 columns
  (SRR, species, layout, mode, per-stage status).
- Atomic writes via `awk > tmp && mv tmp real` — safe against interrupted runs.
- `tracker_is_complete()` via `awk` prevents reprocessing successful samples
  across retry passes.

**Retry loop**
- `PIPELINE_RETRY_PASSES` in `config/pipeline.sh` is wired to a functional
  `for (( pass=1; pass<=PIPELINE_RETRY_PASSES; pass++ ))` loop in `run.sh`.
  In v1 the variable existed but had no outer loop.
- Failed samples are automatically retried on the next pass.

**Trimmer**
- Trimmomatic replaced consistently by **BBDuk** (BBMap suite).
  `_bbduk_args()` builds optional arguments (adapters, k-mer) at runtime;
  mandatory parameters are always appended.
- Removed the inconsistency where `config.sh` declared BBDuk but
  `03_quantify.sh` called Trimmomatic.

**STAR and RSEM decoupled**
- The v1 `step_rsem()` coupled STAR and RSEM in a single function.
  In v2: `steps/align.sh` (`step_star`) and `steps/quantify.sh` (`step_rsem`)
  are independent — RSEM can be re-run against an existing BAM without
  repeating alignment.
- `_STAR_FLAGS` declared as a module-level array in `steps/align.sh`,
  auditable in one place.

**Logging**
- `log_step()` writes to stdout **and** to `logs/<SRR>.log` (cumulative per
  sample). In v1 it only wrote to stdout.
- Each tool has its own per-sample log file:
  `_bbduk.log`, `_star.log`, `_STAR_Log.final.out`, `_rsem.log`.

**Tool validation**
- `check_tools` reports **all** missing binaries before aborting.
  In v1, `check_tool()` aborted on the first missing tool.

**Unit tests**
- `tests/test_pipeline.sh`: 17 bash tests with no external dependencies.
  Covers `normalize_layout` (8 cases), `require_file`, `detect_inputs`, and
  `parse_runtable.py`. Result: 17 passed, 0 failed.

**Integrated post-processing**
- `steps/postprocess.sh` + `helpers/build_matrix.py` run automatically at the
  end of the pipeline. In v1 there was no automatic expression matrix or QC
  matrix generation.

---

### Changes from v1

| Aspect | v1 | v2 |
|:-------|:---|:---|
| Files | 7 | 19 |
| Entry point | `bash 03_quantify.sh` | `bash run.sh [--test\|--full\|--build-refs]` |
| Trimmer | Config declared BBDuk; `03_quantify.sh` called Trimmomatic | BBDuk consistent throughout |
| STAR + RSEM | Coupled in `step_rsem()` | Decoupled into `steps/align.sh` and `steps/quantify.sh` |
| Sample tracker | No | `pipeline_sample_summary.tsv` (atomic writes) |
| Retry loop | No | Functional via `PIPELINE_RETRY_PASSES` |
| Idempotency | `[[ -f genes.results ]]` | `tracker_is_complete()` via TSV |
| Python | Standalone script (`02_prepare_samples.py`) | `argparse` helpers + new `build_matrix.py` |
| Per-sample log | stdout only | `logs/<SRR>.log` cumulative |
| Unit tests | No | 17 tests, no external dependencies |
| Expression matrix | No | `gene_expression_matrix.tsv` + 2 QC matrices |

---

### Bug fixes

- **`(( _pass++ ))` under `set -e`:** post-increment evaluates the old value
  (0 on the first iteration), which is falsy in bash arithmetic, causing an
  immediate exit with code 1 when `_pass=0`. Fixed to `(( ++_pass ))`.
- **`exit 1` in `require_file` kills the test process:** `assert_fails` in
  `tests/test_pipeline.sh` now wraps the command in a subshell `( "$@" )` so
  that `exit 1` only exits the subshell, not the test runner.
- **`PIPELINE_RETRY_PASSES` declared but never consumed (v1):** the variable
  existed in `config.sh` but there was no outer loop in `03_quantify.sh`.
  Fixed in v2 with `for (( pass=1; ... ))` in `run.sh`.
- **Trimmer inconsistency (v1):** `config.sh` set `TRIMMER="bbduk"` but the
  quantification scripts called Trimmomatic. Unified to BBDuk throughout.

---

## v1.0.0 — 2026-06 — Original modular pipeline

First modular version: `config.sh`, `00_setup.sh`, `01_build_references.sh`,
`02_prepare_samples.py`, `03_quantify.sh`, `lib/utils.sh`, `lib/cleanup.sh`.
Separated configuration, reference building, sample parsing, and quantification
into distinct files. Introduced `check_all_tools` (reports all missing tools),
`lib/cleanup.sh`, and `lib/utils.sh`. Had a trimmer inconsistency (config
declared BBDuk, scripts called Trimmomatic) and no sample tracker or retry loop.
