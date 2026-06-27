# Release Notes — Lepidoptera RNA-seq TPM Pipeline

---

## v3.0.0 — 2026-06-26 — Full modular refactor (`pipeline/`)

### Resumen

Reescritura completa del pipeline a partir de la versión monolítica (`02_run_pipeline.sh`).
El código Python embebido como heredoc fue extraído a helpers independientes,
el trimmer fue unificado a BBDuk, se añadió un rastreador atómico de muestras,
un bucle de reintentos funcional y una suite de pruebas unitarias.

---

### Nuevo en v3

**Arquitectura**
- Pipeline reorganizado en `config/`, `lib/`, `steps/`, `helpers/` y `tests/`.
  19 archivos; un único punto de entrada: `bash pipeline/run.sh`.
- Cada etapa del análisis ocupa su propio archivo en `steps/`:
  `validate_inputs`, `build_references`, `parse_samples`, `prefetch`,
  `fastq_dump`, `fastqc`, `trim`, `align`, `quantify`, `postprocess`.

**Configuración**
- `config/species.sh`: array multi-especie con campo `active` (true/false).
  Agregar o desactivar una especie no requiere modificar código.
- `config/pipeline.sh`: todas las variables de ejecución en un único archivo
  sin valores duplicados entre módulos.

**Helpers Python independientes**
- `helpers/parse_runtable.py`: CLI con `argparse`; acepta `.csv` y `.xlsx`;
  reemplaza el bloque Python embebido (líneas 260–663 de `02_run_pipeline.sh`).
- `helpers/build_matrix.py`: genera `gene_expression_matrix.tsv` (inner join
  de todos los `genes.results`), `STAR_mapping_QC_matrix.tsv` y
  `BBDUK_preprocessing_QC_matrix.tsv`.

**Rastreo de muestras**
- `lib/sample_tracker.sh`: `pipeline_sample_summary.tsv` con 11 columnas
  (SRR, especie, layout, modo, estado por etapa).
- Escrituras atómicas: `awk > tmp && mv tmp real` — seguro ante interrupciones.
- `tracker_is_complete()` via `awk` evita reprocesar muestras exitosas entre
  pasadas del bucle de reintentos.

**Bucle de reintentos**
- `PIPELINE_RETRY_PASSES` en `config/pipeline.sh` ahora está conectado a un
  bucle `for (( pass=1; pass<=PIPELINE_RETRY_PASSES; pass++ ))` funcional en
  `run.sh`. En v2 la variable existía pero no tenía bucle externo.
- Muestras fallidas se reintentan automáticamente en la siguiente pasada.

**Trimmer**
- Trimmomatic reemplazado por **BBDuk** (BBMap suite) de forma consistente.
  `_bbduk_args()` construye argumentos opcionales (adaptadores, k-mer) en
  runtime; parámetros obligatorios siempre presentes.
- Eliminada la inconsistencia entre `config.sh` (definía BBDuk) y
  `03_quantify.sh` (llamaba a Trimmomatic) que existía en v1 y v2.

**STAR y RSEM separados**
- `step_rsem()` de v1/v2 acoplaba STAR y RSEM en una sola función.
  En v3: `steps/align.sh` (`step_star`) y `steps/quantify.sh` (`step_rsem`)
  son independientes — es posible re-ejecutar sólo RSEM sobre un BAM existente.
- `_STAR_FLAGS` declarado como array a nivel de módulo en `steps/align.sh`,
  auditables en un solo lugar.

**Logging**
- `log_step()` escribe a stdout **y** a `logs/<SRR>.log` (acumulativo por
  muestra). En v1/v2 sólo escribía a stdout.
- Cada herramienta tiene su propio archivo de log por muestra:
  `_bbduk.log`, `_star.log`, `_STAR_Log.final.out`, `_rsem.log`.

**Validación de herramientas**
- `check_tools` reporta **todos** los binarios faltantes antes de abortar.
  En v2, `check_tool()` abortaba al primer faltante.

**Pruebas unitarias**
- `tests/test_pipeline.sh`: 17 pruebas bash sin dependencias externas.
  Cubre `normalize_layout` (8 casos), `require_file`, `detect_inputs` y
  `parse_runtable.py`. Resultado: 17 passed, 0 failed.

**Post-procesamiento integrado**
- `steps/postprocess.sh` + `helpers/build_matrix.py` integrados en el flujo
  principal. En v1/v2 no existía generación automática de matrices de expresión
  ni de QC al finalizar el pipeline.

---

### Cambios respecto a v2 (`02_run_pipeline.sh`)

| Aspecto | v2 | v3 |
|:--------|:---|:---|
| Archivos | 2 (`01_config.sh` + `02_run_pipeline.sh`) | 19 archivos en `pipeline/` |
| Python | Heredoc embebido (líneas 260–663) | Scripts independientes con `argparse` |
| Trimmer | Trimmomatic | BBDuk |
| Soporte multi-especie | Una especie por ejecución (`SPECIES_NAME`) | N especies con flag `active` |
| Rastreador de muestras | No | `pipeline_sample_summary.tsv` atómico |
| Bucle de reintentos | Variable declarada, sin bucle | Bucle funcional `for pass in 1..N` |
| `check_tools` | Aborta al primer faltante | Reporta todos los faltantes |
| STAR + RSEM | Acoplados en `step_rsem()` | `steps/align.sh` + `steps/quantify.sh` independientes |
| Log por muestra | No | `logs/<SRR>.log` acumulativo |
| Pruebas unitarias | No | 17 pruebas, 0 dependencias externas |
| Matrices de expresión | No | `gene_expression_matrix.tsv` + 2 matrices QC |

---

### Cambios respecto a v1 (`config.sh` + `03_quantify.sh` + `lib/`)

| Aspecto | v1 | v3 |
|:--------|:---|:---|
| Archivos | 7 | 19 |
| Trimmer | Config definía BBDuk; `03_quantify.sh` llamaba Trimmomatic (inconsistencia) | BBDuk consistente en config y en `steps/trim.sh` |
| STAR + RSEM | Acoplados en `step_rsem()` | Separados en `align.sh` y `quantify.sh` |
| Rastreador de muestras | No | `pipeline_sample_summary.tsv` |
| Bucle de reintentos | No | Funcional con `PIPELINE_RETRY_PASSES` |
| Idempotencia | `[[ -f genes.results ]]` | `tracker_is_complete()` vía TSV |
| Python | Script autónomo (`02_prepare_samples.py`) | Helpers con `argparse` + `build_matrix.py` adicional |
| Pruebas unitarias | No | 17 pruebas |

---

### Bugs corregidos

- **`(( _pass++ ))` bajo `set -e`:** el post-incremento evalúa el valor anterior
  (0 en la primera iteración), que es falso para bash aritmético, causando
  salida inmediata con código 1 cuando `_pass=0`. Corregido a `(( ++_pass ))`.
- **`exit 1` en `require_file` mata el proceso de pruebas:** `assert_fails` en
  `tests/test_pipeline.sh` ahora envuelve el comando en subshell `( "$@" )` para
  que `exit 1` sólo termine el subshell.
- **`PIPELINE_RETRY_PASSES` declarado pero no consumido (v2):** la variable
  existía en `01_config.sh` pero no había bucle externo en `02_run_pipeline.sh`.
  Corregido en v3 con bucle `for (( pass=1; ... ))` en `run.sh`.
- **Inconsistencia de trimmer (v1 y v2):** `config.sh` definía `TRIMMER="bbduk"`
  pero los scripts de cuantificación invocaban Trimmomatic. Unificado a BBDuk.

---

## v2.0.0 — 2026-06 — Pipeline monolítico refactorizado

Refactor intermedio a partir de v1. Consolidó todo el flujo en `02_run_pipeline.sh`
con funciones bien delimitadas. Introdujo `PREFETCH_RETRIES`, `PIPELINE_RETRY_PASSES`
(sin bucle), `detect_inputs()` y el bloque Python como heredoc para parsear
el RunTable. Mejoró el logging con timestamps. No resolvió la separación
STAR/RSEM ni añadió rastreador de muestras.

---

## v1.0.0 — 2026-06 — Pipeline modular original

Primera versión modular: `config.sh`, `00_setup.sh`, `01_build_references.sh`,
`02_prepare_samples.py`, `03_quantify.sh`, `lib/utils.sh`, `lib/cleanup.sh`.
Separó configuración, referencias, parseo de muestras y cuantificación en
archivos distintos. Introdujo `check_all_tools` (reporta todos los faltantes),
`lib/cleanup.sh` y `lib/utils.sh`. Presentó inconsistencia de trimmer
(config BBDuk vs. ejecución Trimmomatic) y sin rastreador de muestras.
