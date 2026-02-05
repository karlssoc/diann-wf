# Library Parameter Analysis: Human/Yeast LFQ-Bench

Analysis of DIA-NN report and predicted spectral library to determine optimal
library generation parameters that maximize proteome coverage while minimizing
search space.

**Date:** 2026-02-05

## Data Sources

- **Report:** DIA-NN quantification of human/yeast LFQ-Bench mixture (timsTOF)
  - Tuned with `ttht-biognosys` preset
  - Path: `lfq-bench-analysis/data/input/quant/2511-2512/2.2_tune_ttht-biognosys/tuned/ttht-biognosys/report.parquet`
- **Library:** Predicted spectral library (tuned)
  - Path: `kraken:/srv/data1/karlssoc/projects/tt/lfqb_v2/results/2.2_tune_ttht-biognosys/tuned_library/lfqb_tuned_ttht-biognosys_tuned.predicted.speclib`
  - Converted to parquet for analysis (871 MB speclib -> 527 MB parquet)

## Summary Statistics

|  | Report (1% FDR, unique) | Library (unique precursors) |
|--|------------------------|-----------------------------|
| Total precursors | 131,501 | 3,776,186 |
| Fragment rows | 660,977 | 44,865,777 |

## Precursor m/z (Precursor.Mz)

**Report:** Range 350.2–1349.7, median 625.8, 99% within 383–1142 m/z

**Library:** Range 350.1–1349.9 (already generated with matching bounds)

| Min | Max | Report Coverage | Library Entries | Library Reduction |
|-----|-----|----------------|----------------|-------------------|
| 300 | 1800 | 100.0% | 100.0% | 0.0% |
| 350 | 1650 | 100.0% | 100.0% | 0.0% |
| 350 | 1200 | 99.5% | 93.8% | 6.2% |
| 400 | 1200 | 97.5% | 85.0% | 15.0% |

**Finding:** Library was already well-bounded at 350–1350 m/z. Limited room for
tightening without losing coverage. The report range matches the library range.

## Precursor Charge (Precursor.Charge)

| Charge | Report (IDs) | Library (precursors) |
|--------|-------------|---------------------|
| 1 | 2,089 (1.6%) | 584,265 (15.5%) |
| 2 | 86,330 (65.6%) | 1,266,269 (33.5%) |
| 3 | 38,957 (29.6%) | 1,121,292 (29.7%) |
| 4 | 4,125 (3.1%) | 804,360 (21.3%) |

| Range | Report Coverage | Library Reduction |
|-------|----------------|-------------------|
| z2–3 | 95.3% | 36.2% |
| z2–4 | 98.4% | 14.7% |
| z1–4 | 100.0% | 0.0% |

**Finding:** Biggest optimization opportunity. Charge 1 accounts for 15.5% of
library space but only 1.6% of identifications. Charge 4 is 21.3% of library
but only 3.1% of IDs. Restricting to z2–4 gives 98.4% coverage with 14.7%
reduction; z2–3 gives 95.3% coverage with 36.2% reduction.

## Peptide Length (Stripped.Sequence)

**Report:** Range 7–30, median 13, 98.2% within 7–25

| Range | Report Coverage | Library Reduction |
|-------|----------------|-------------------|
| 7–30 | 100.0% | 0.0% |
| 7–25 | 98.2% | 6.2% |
| 7–20 | 91.8% | 18.8% |
| 8–25 | 93.8% | 12.4% |

**Finding:** Modest gains. Capping at length 25 loses only 1.8% of IDs while
removing 6.2% of library space.

## Combined Parameter Scenarios

| Scenario | Library Precursors | Reduction |
|----------|--------------------|-----------|
| Current (350–1350, z1–4, len 7–30) | 3,776,186 | 0.0% |
| **Conservative (350–1350, z2–4, len 7–25)** | **2,961,457** | **21.6%** |
| Balanced (350–1200, z2–4, len 7–25) | 2,868,176 | 24.0% |
| Aggressive (400–1200, z2–3, len 7–25) | 1,991,247 | 47.3% |
| Max reduction (400–1200, z2–3, len 8–20) | 1,685,801 | 55.4% |

## Recommended Parameters

**Conservative** — best balance for applying to a different sample type:

```yaml
library:
  min_pr_mz: 350
  max_pr_mz: 1350
  min_pr_charge: 2
  max_pr_charge: 4
  min_pep_len: 7
  max_pep_len: 25
  min_fr_mz: 200
  max_fr_mz: 1800
  cut: 'K*,R*'
  missed_cleavages: 1
```

This drops charge 1 (15.5% of library, 1.6% of IDs) and long peptides >25
(6.2% of library, 1.8% of IDs), for a combined 21.6% library size reduction
with ~98% identification coverage.

## Caveats

- Parameters derived from a human/yeast LFQ-Bench mixture on timsTOF
- Different sample types, organisms, or instruments may have different
  optimal ranges (e.g., charge 4 may be more important for larger proteins)
- Library reduction percentages are at the precursor level; fragment-level
  reduction may differ
- These parameters were extracted from a tuned library that already had
  constrained m/z bounds (350–1350)

## Reproducing This Analysis

```bash
python bin/analyze_library_params.py \
  --report path/to/report.parquet \
  --library path/to/library.parquet
```
