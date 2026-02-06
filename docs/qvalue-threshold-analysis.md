# Q-value Threshold Analysis for Iterative Quantification

## Background

DIA-NN's `--qvalue` flag controls the precursor-level FDR threshold applied when writing `report.parquet`. The default is 0.01 (1% FDR). In the iterative quantification workflow, the identification stage report is used to determine which Protein.Groups to include in the subset library. A stricter threshold means fewer PGs make it into the subset, potentially excluding true positives from the final MBR stage.

## Experiment

Tested `--qvalue` at 0.01, 0.05, 0.10, and 0.20 on two real datasets (kraken, single RAW file each):

| Dataset | FASTA | Q=0.01 | Q=0.05 | Q=0.10 | Q=0.20 |
|---------|-------|--------|--------|--------|--------|
| Mouse plasma | UP000000589 | 1,359 PGs | 1,774 PGs | 1,774 PGs | 1,774 PGs |
| Human | UP000005640 | 6,054 PGs | 7,048 PGs | 7,048 PGs | 7,048 PGs |

## Key Findings

- **0.05 captures significantly more PGs**: +31% for mouse, +16% for human vs default 0.01
- **Saturation at 0.05**: No additional PGs at 0.10 or 0.20 — diminishing returns beyond 5% FDR
- **Safe for subsetting**: The relaxed threshold only applies to the identification stage. The final quantification stage still uses the default 0.01 FDR, so the final results maintain strict FDR control.

## Implementation

`qvalue_identify: 0.05` in `configs/workflows/iterative_quant.yaml` passes `--qvalue 0.05` to the identification stage QUANTIFY call. The final stage uses DIA-NN's default (0.01).

Additionally, `--reannotate` is now automatically added when using `.parquet` libraries to restore proteotypic peptide annotations lost during speclib-to-parquet conversion.

## Data Location

Raw results: `kraken:/srv/data1/karlssoc/projects/sepfw/baboon-mouse/results/man_run/`
- `2_mouse_plasma_1/` — mouse plasma reports at 4 q-value thresholds
- `2_human_1/` — human reports at 4 q-value thresholds
