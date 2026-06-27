#!/usr/bin/env python3
"""Parses an NCBI SRA RunTable (CSV or XLSX) and writes samples.tsv."""

import argparse
import csv
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Optional

ACCESSION_RE = re.compile(r"^[SED]RR\d+$")

SPECIES_MAP = {
    "spodoptera frugiperda":  "Spodoptera_frugiperda",
    "plutella xylostella":    "Plutella_xylostella",
    "diatraea saccharalis":   "Diatraea_saccharalis",
    "bombyx mori":            "Bombyx_mori",
    "tecia solanivora":       "Tecia_solanivora",
    "phyllocnistis citrella": "Phyllocnistis_citrella",
    "helicoverpa armigera":   "Helicoverpa_armigera",
}


def _load(path: Path) -> list[dict]:
    if path.suffix.lower() in {".xlsx", ".xls"}:
        try:
            import openpyxl
        except ImportError:
            sys.exit("[ABORT] openpyxl not installed: pip install openpyxl")
        wb   = openpyxl.load_workbook(str(path), read_only=True)
        rows = list(wb.worksheets[0].iter_rows(values_only=True))
        wb.close()
    else:
        with path.open("r", encoding="utf-8-sig", newline="") as fh:
            rows = [tuple(r) for r in csv.reader(fh)]

    if not rows:
        sys.exit(f"[ABORT] RunTable is empty: {path}")

    headers = [str(h).strip() if h is not None else f"col_{i}"
               for i, h in enumerate(rows[0])]
    return [dict(zip(headers, row)) for row in rows[1:]
            if any(v is not None and str(v).strip() for v in row)]


def _get(row: dict, *keys: str) -> str:
    for k in keys:
        v = row.get(k)
        if v is not None and str(v).strip():
            return str(v).strip()
    return ""


def _species(organism: str, fallback: Optional[str]) -> Optional[str]:
    org = organism.lower()
    return next((v for k, v in SPECIES_MAP.items() if k in org), fallback)


def _layout(raw: str) -> str:
    v = raw.strip().upper().replace("-", " ").replace("_", " ")
    if v in {"PAIRED", "PAIRED END", "PE"}:
        return "PAIRED"
    if v in {"SINGLE", "SINGLE END", "SE"}:
        return "SINGLE"
    return ""


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--input",    "-i", required=True, type=Path)
    p.add_argument("--output",   "-o", default="samples.tsv", type=Path)
    p.add_argument("--fallback", "-f", default=None)
    args = p.parse_args()

    if not args.input.exists():
        sys.exit(f"[ABORT] Input not found: {args.input}")

    all_rows = _load(args.input)
    print(f"[INFO] RunTable loaded: {len(all_rows)} records.")

    rnaseq = [r for r in all_rows
              if _get(r, "Assay Type", "AssayType", "assay_type") == "RNA-Seq"]
    print(f"[INFO] After RNA-Seq filter: {len(rnaseq)}")

    sourced = [r for r in rnaseq
               if _get(r, "LibrarySource", "Library Source", "library_source")
               in {"TRANSCRIPTOMIC", "GENOMIC"}]
    if not sourced:
        print("[WARN] No records passed LibrarySource filter — using all RNA-Seq rows.")
        sourced = rnaseq

    mapped = []
    for r in sourced:
        sp = _species(_get(r, "Organism", "organism", "scientific_name"), args.fallback)
        if sp:
            mapped.append({**r, "_sp": sp})

    seen:  set   = set()
    clean: list  = []
    for r in mapped:
        srr = _get(r, "Run", "Run Accession", "RunAccession", "Accession").replace("\r", "")
        if not ACCESSION_RE.match(srr) or srr in seen:
            continue
        seen.add(srr)
        layout = _layout(_get(r, "LibraryLayout", "Library Layout", "library_layout"))
        if not layout:
            print(f"[WARN] Unknown layout for {srr} — defaulting to PAIRED.")
            layout = "PAIRED"
        clean.append({"SRR": srr, "SPECIES": r["_sp"], "LAYOUT": layout})

    if not clean:
        sys.exit("[ABORT] No valid RNA-Seq samples found.")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["SRR", "SPECIES", "LAYOUT"],
                           delimiter="\t", lineterminator="\n")
        w.writeheader()
        w.writerows(clean)

    by_layout  = Counter(r["LAYOUT"]  for r in clean)
    by_species = Counter(r["SPECIES"] for r in clean)
    print(f"[DONE] {len(clean)} samples written to: {args.output}")
    print(f"       Layout  : {dict(by_layout)}")
    for sp, n in sorted(by_species.items()):
        print(f"       {sp}: {n}")


if __name__ == "__main__":
    main()
