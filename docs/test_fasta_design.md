# Test FASTA Design for Model Preset Validation

**Status:** On hold
**Last updated:** 2025-01-29

## Goal

Create a small, universal test FASTA containing proteins conserved across species (human, mouse, yeast) to validate that `model_preset` configurations improve RT/IM prediction accuracy before running full analyses.

## Rationale

- Pre-trained models (RT, IM) may not generalize to all datasets
- FR tuning does not generalize well (skip for now)
- Quick validation with ultrafast quantification (no MBR) can catch mismatched presets early
- Compare: default models vs preset models → ID rates, RT prediction error

## Research Summary

### Key Resources

1. **CiRT Paper (2015)** - [PMC4597153](https://pmc.ncbi.nlm.nih.gov/articles/PMC4597153/)
   - 14 conserved peptides from: Actin, HSP70/90, ribosomal proteins, 14-3-3, ADP/ATP translocase
   - Selection: peptides in human + yeast data AND top 500 most frequent in UniProt

2. **PAXdb v6.0** - [pax-db.org](https://pax-db.org)
   - Protein abundance database: 1639 datasets, 392 species
   - Abundance in ppm (parts per million)
   - Orthology via eggNOG

3. **Stable housekeeping proteins** (from literature):
   - GAPDH, ACTB, TMSB4X, EEF1A1, PPIA, CFL1, ENO1

## Data Downloaded

Located in `/Users/karlssoc/Downloads/`:

```
paxdb-mapped_peptides-v6.0/     # ~193MB, peptide-level data
  - 9606-*.peptide              # Human (234 datasets)
  - 10090-*.peptide             # Mouse (88 datasets)
  - 4932-*.peptide              # Yeast (11 datasets)

paxdb-uniprot-links-v6.0/
  - paxdb_uniprot_linkins_ids.tsv   # PAXdb ID → UniProt mapping
```

**File format** (peptide files):
```
#string_external_id    peptide_sequence    spectral_count
9606.ENSP00000295897   LVNEVTEFAK          12345
```

## Analysis Progress

### Scripts Created

Located in scratchpad (session-specific):
- `analyze_paxdb.py` - Aggregates spectral counts per protein per species
- `find_orthologs.py` - Maps gene families across species (incomplete)

### Preliminary Results

**Top abundant proteins by species:**

| Human | Mouse | Yeast |
|-------|-------|-------|
| ALBU (Albumin) | ACTB (Actin) | ENO2 (Enolase) |
| HBB (Hemoglobin β) | ACTG (Actin) | G3P3 (GAPDH) |
| ACTB (Actin) | ACTS (Actin) | PDC1 (Pyruvate decarb.) |
| ACTG (Actin) | ACTC (Actin) | EF1A (Elongation factor) |
| HBA (Hemoglobin α) | ACTA (Actin) | KPYK1 (Pyruvate kinase) |

**Conserved families (all 3 species):**
- Actins (ACT)
- GAPDH (G3P)
- Enolases (ENO)
- Elongation factors (EF1A)
- Heat shock proteins (HSP70, HSP90)
- Phosphoglycerate kinase (PGK)
- Tubulins (TBA, TBB)
- Histones (H2A, H2B, H3, H4)
- Ribosomal proteins

## Proposed Test FASTA Composition

~200-500 proteins:

| Category | Source | Count |
|----------|--------|-------|
| Conserved housekeeping | PAXdb intersection (human/mouse/yeast) | ~50-100 |
| CiRT validated | Actin, HSPs, ribosomal, 14-3-3 | ~20 |
| Plasma markers | Albumins (multi-species), transferrin | ~10 |
| Contaminants | Trypsin, keratins (cRAP database) | ~20 |
| Species-specific QC | Unique markers per species | ~10 |

## Validation Workflow Design

```
┌─────────────────────────────────────────────────────────┐
│  validate_preset.nf                                     │
├─────────────────────────────────────────────────────────┤
│  1. Quantify test sample with DEFAULT models            │
│     → baseline_report.parquet                           │
│                                                         │
│  2. Quantify test sample with PRESET models             │
│     → preset_report.parquet                             │
│                                                         │
│  3. Compare metrics:                                    │
│     - Precursor IDs at 1% FDR                          │
│     - Median RT prediction error                        │
│     - P90 RT prediction error                          │
│     - IM error (if applicable)                         │
│                                                         │
│  4. Report: PASS/WARN based on thresholds              │
└─────────────────────────────────────────────────────────┘
```

**DuckDB comparison query:**
```sql
SELECT
  COUNT(*) as precursor_ids,
  MEDIAN(ABS(RT - "Predicted.RT")) as median_rt_error,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY ABS(RT - "Predicted.RT")) as p90_rt_error
FROM 'report.parquet'
WHERE "Q.Value" < 0.01
```

## Next Steps

1. [ ] Run `find_orthologs.py` to complete cross-species mapping
2. [ ] Extract UniProt IDs for conserved proteins
3. [ ] Download sequences from UniProt (human canonical)
4. [ ] Add contaminants from cRAP database
5. [ ] Create `test_data/test_proteome.fasta`
6. [ ] Implement `workflows/validate_preset.nf`
7. [ ] Define pass/fail thresholds for RT error

## References

- Parker SJ et al. (2015) "Identification of a Set of Conserved Eukaryotic Internal Retention Time Standards" [PMID: 26199342](https://pubmed.ncbi.nlm.nih.gov/26199342/)
- Huang Q et al. (2023) "PaxDb 5.0" [PMID: 37659604](https://pubmed.ncbi.nlm.nih.gov/37659604/)
- PAXdb v6.0 (2024) [NAR Database Issue](https://academic.oup.com/nar/advance-article/doi/10.1093/nar/gkaf1066/8313448)
