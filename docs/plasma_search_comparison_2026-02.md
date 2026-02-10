# Plasma Search Space Comparison (Feb 2026)

## Objective

Determine whether search space reduction (iterative or manual FASTA pre-filtering) is still necessary with DIA-NN 2.3.2 for mouse plasma samples.

## Dataset

- 81 mouse plasma samples (timsTOF dia-PASEF, `.dia` files)
- Full mouse proteome: UP000000589_10090.fasta (21,821 proteins)
- Pre-filtered plasma FASTA: UP000000589_10090_plasma.fasta (2,409 proteins)
- Model preset: `hfx-vneo-16SPD-2.3.2-260608`
- Server: kraken (alap759)
- File sizes: 329-791 MB per .dia file (median ~670 MB)

## Searches

| Run | Workflow | FASTA | Library precursors | individual_mass_acc | Charge | Threads | Time |
|-----|----------|-------|--------------------|---------------------|--------|---------|------|
| nf-4 | ITERATIVE_QUANT | Full proteome | 3.7M -> subset 557K | No | 1-4 | 60 | ~5h 20m |
| nf-5 | LIBRARY_AND_QUANTIFY | Pre-filtered plasma | 494K | Yes | 1-4 | 60 | ~2h 35m |
| nf-6 | LIBRARY_AND_QUANTIFY | Full proteome | 2.3M | Yes | 2-3 | 96 | ~10h (manual) |

Notes:
- nf-6 timed out in Nextflow at file 66/81, was completed manually with 96 threads
- nf-4 used calibration library from InfinDIA presearch; nf-5 and nf-6 did not

Configs: `kraken:/srv/data1/karlssoc/projects/DT-D3mNP-pquant/config/nf-{4,5,6}-*.yaml`
Results: `kraken:/srv/data1/karlssoc/projects/DT-D3mNP-pquant/results/nf-{4,5,6}-*/`

## Three-Way Comparison

### Per-sample means (81 samples)

| Metric | nf-4 (iterative) | nf-5 (prefiltered) | nf-6 (full proteome) |
|--------|------------------|-------------------|---------------------|
| Precursors/sample | 10,422 | **11,222** | 9,066 |
| Proteins/sample | 916 | **921** | 882 |

### Protein groups in matrix (1% FDR, MBR)

| Metric | nf-4 (iterative) | nf-5 (prefiltered) | nf-6 (full proteome) |
|--------|------------------|-------------------|---------------------|
| Total PGs | **1,671** | 1,463 | 1,522 |
| Unique genes | **1,626** | 1,423 | 1,483 |

### Data quality

| Metric | nf-4 (iterative) | nf-5 (prefiltered) | nf-6 (full proteome) |
|--------|------------------|-------------------|---------------------|
| Data completeness | 58.2% | **67.0%** | 61.4% |
| PGs 100% complete | 375 (22.4%) | **407 (27.8%)** | 378 (24.8%) |
| PGs >=90% complete | 610 (36.5%) | **667 (45.6%)** | 603 (39.6%) |
| PGs >=70% complete | 769 (46.0%) | **808 (55.2%)** | 757 (49.7%) |
| PGs <50% complete | 772 (46.2%) | **520 (35.5%)** | 626 (41.1%) |
| 1-precursor proteins | 199 (11.9%) | **77 (5.3%)** | 208 (13.5%) |
| Precursors/protein (avg) | 11.9 | **14.0** | 10.9 |

### Protein overlap

| Comparison | Shared | Only A | Only B |
|------------|--------|--------|--------|
| nf-5 vs nf-6 | 1,349 | 114 (nf-5 only) | 173 (nf-6 only) |
| nf-4 vs nf-6 | 1,407 | 264 (nf-4 only) | 115 (nf-6 only) |
| All three | 1,322 | - | - |
| Union all | 1,822 | - | - |

### nf-6 vs nf-5: per-file precursor loss

Searching the full proteome (2.3M precursors) instead of the pre-filtered FASTA (494K precursors) costs ~19% precursor IDs per sample:

| | Mean | Median | Min | Max |
|--|------|--------|-----|-----|
| Precursor change | -19.3% | -19.4% | -27.4% | -12.8% |

Both batches (M2512, M2601) are equally affected (~19%).

### nf-6 vs nf-5: shared protein quality

For the 1,349 proteins found in both searches:
- **747 proteins** have better completeness in nf-5
- **119 proteins** have better completeness in nf-6
- **483 proteins** similar (within 1%)
- Average completeness difference: **-4.6%** (nf-6 worse)

The 173 proteins unique to nf-6 are mostly low quality:
- Average completeness: 30.3%
- Only 37/173 have >=50% completeness
- 104/173 have <20% completeness

## ITERATIVE_QUANT Pipeline Stages

| Stage | Duration | Notes |
|-------|----------|-------|
| GENERATE_LIBRARY (full) | 4m 9s | 3.7M precursors, cached |
| GENERATE_LIBRARY_IDENTIFY (narrow) | 2m 34s | 2M precursors (charge 1-4) |
| CONVERT_LIBRARY x2 | 3m 19s | .speclib -> .parquet |
| INFINDIA_PRESEARCH (3 files) | 2m 53s | Calibration on 3 representative files |
| SUBSET_LIBRARY_PEPTIDE | 6s | Presearch peptides -> subset identify library |
| QUANTIFY_IDENTIFY (81 files) | **3h 47m** | Bottleneck: 81 files x 2M precursors at 5% FDR |
| SUBSET_LIBRARY | 8.5s | 2,807 PGs -> 557K precursors (84.9% reduction) |
| QUANTIFY_FINAL (81 files) | 1h 23m | 557K precursors |

## Key Findings

1. **Search space reduction matters significantly for plasma.** nf-6 (full proteome, 2.3M precursors) loses ~19% precursor IDs per sample compared to nf-5 (pre-filtered, 494K precursors). The larger search space introduces noise and false positives that compete with true identifications.

2. **Pre-filtered FASTA (nf-5) is the clear winner on data quality.** Best completeness (67%), fewest 1-precursor proteins (5.3%), most precursors per protein (14.0). The focused search space lets DIA-NN work most efficiently.

3. **ITERATIVE_QUANT (nf-4) finds the most PGs (1,671) but at poor quality.** Many extra proteins are marginal: 12% are single-precursor, and overall completeness is only 58%. The 271 PGs unique to nf-4 are largely noise. Also did not use `--individual-mass-acc`.

4. **nf-6 (full proteome, simple) sits in between** — more PGs than nf-5 but worse quality on every metric. The 173 extra PGs are overwhelmingly low quality (104/173 have <20% completeness).

5. **`--individual-mass-acc` is important** but does not overcome search space effects. nf-6 used it and still performed worse than nf-5.

6. **Search space reduction is still necessary** with DIA-NN 2.3.2 for plasma proteomics with large FASTA files.

## Conclusions

**For plasma (and likely other low-complexity samples): pre-filter your search space.**

The question is how:

### Option A: Manual FASTA pre-filtering (current nf-5 approach)
- **Best results**: 67% completeness, 14 precursors/protein
- **Fastest**: ~2.5h
- **Limitation**: Requires prior knowledge of which proteins are present
- **Best for**: Well-characterized sample types where a reduced FASTA already exists

### Option B: Simplified presearch (recommended new approach)
- Search 3-5 representative files against full proteome (~15-20 min)
- Extract protein list at relaxed FDR
- Subset library by detected proteins
- Search all files against subset library (~2-2.5h)
- **Total**: ~3h (vs 5h 20m for full ITERATIVE_QUANT)
- **Best for**: New sample types where you don't know the proteome composition

### Option C: Full ITERATIVE_QUANT (current nf-4 approach)
- Most PGs, but worst quality per PG
- Slowest (5h 20m), bottleneck is searching ALL files for identification
- The identification stage (81 files x full library) is overkill — a few files suffice
- **Not recommended** unless you need maximum protein coverage regardless of quality

### Not recommended: Full proteome without reduction (nf-6)
- 19% precursor loss, worse completeness, more 1-hit wonders
- Slowest per-file search time due to large library
- The extra PGs found are almost all low quality

## Suggested Next Steps

1. **Implement Option B** as a simplified workflow: presearch on N files -> subset -> full quantification
2. **Test with N=3, 5, 10 files** to find the minimum needed for good coverage
3. **Add `--individual-mass-acc` to ITERATIVE_QUANT** to remove the confound for future comparisons
4. **Consider charge 2-3 as default** for the quantification library (charge 1-4 for presearch only)
