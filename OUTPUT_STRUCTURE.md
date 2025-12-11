# Full Pipeline Output Structure

This document explains how outputs are organized when running the full multi-round pipeline.

## Overview: Data Flow

```
ROUND 1 (Default Models)
  ├─→ GENERATE_LIBRARY (default) → library_r1.predicted.speclib
  └─→ QUANTIFY (all samples)     → sample1/out-lib.parquet
                                 → sample2/out-lib.parquet
                                 → sample3/out-lib.parquet

TUNING (using specified sample)
  └─→ TUNE_MODELS (sample2)      → out-lib.dict.txt
                                 → out-lib.tuned_rt.pt
                                 → out-lib.tuned_im.pt
                                 → out-lib.tuned_fr.pt

ROUND 2 (RT+IM Tuned Models)
  ├─→ GENERATE_LIBRARY (RT+IM)  → library_r2.predicted.speclib
  └─→ QUANTIFY (all samples)     → sample1/report.parquet
                                 → sample2/report.parquet
                                 → sample3/report.parquet

ROUND 3 (RT+IM+FR Tuned Models)
  ├─→ GENERATE_LIBRARY (RT+IM+FR) → library_r3.predicted.speclib
  └─→ QUANTIFY (all samples)       → sample1/report.parquet
                                   → sample2/report.parquet
                                   → sample3/report.parquet
```

## Complete Directory Structure

When you run the full pipeline with `outdir: 'results'`, you get:

```
results/
│
├── library/                           # From GENERATE_LIBRARY processes
│   ├── library_r1.predicted.speclib   # Round 1: Default models
│   ├── library_r1.tsv                 # (optional)
│   ├── library_generation.log
│   │
│   ├── library_r2.predicted.speclib   # Round 2: RT+IM tuned
│   ├── library_r2.tsv
│   ├── library_generation.log
│   │
│   ├── library_r3.predicted.speclib   # Round 3: RT+IM+FR tuned
│   ├── library_r3.tsv
│   └── library_generation.log
│
├── tuning/                            # From TUNE_MODELS process
│   ├── out-lib.dict.txt               # Tokenization dictionary
│   ├── out-lib.tuned_rt.pt            # Retention time model
│   ├── out-lib.tuned_im.pt            # Ion mobility model
│   ├── out-lib.tuned_fr.pt            # Fragment intensity model (2.3.1+)
│   └── tune.log                       # Tuning log
│
├── mann/                              # From QUANTIFY processes (sample 1)
│   ├── report.parquet                 # Main quantification results
│   ├── out-lib.parquet                # Output library (used for tuning if tune_sample)
│   ├── *.tsv                          # Matrix files (if --matrices enabled)
│   │   ├── pg.matrix.tsv              # Protein group matrix
│   │   ├── pr.matrix.tsv              # Precursor matrix
│   │   └── ...
│   └── diann.log                      # DIANN execution log
│
├── p2/                                # Sample 2
│   ├── report.parquet
│   ├── out-lib.parquet
│   ├── *.tsv
│   └── diann.log
│
├── std/                               # Sample 3
│   ├── report.parquet
│   ├── out-lib.parquet
│   ├── *.tsv
│   └── diann.log
│
└── pipeline_info/                     # Nextflow execution reports
    ├── execution_report.html          # Resource usage statistics
    ├── execution_timeline.html        # Timeline visualization
    ├── execution_trace.txt            # Detailed trace
    └── pipeline_dag.svg               # Workflow diagram
```

## Detailed Module Outputs

### Module: GENERATE_LIBRARY

**Location:** `results/library/`

**Outputs:**
```groovy
process GENERATE_LIBRARY {
    publishDir "${params.outdir}/library"

    output:
    path "${library_name}.predicted.speclib", emit: library   // Main spectral library
    path "${library_name}.tsv", emit: tsv, optional: true     // TSV format (optional)
    path "library_generation.log", emit: log                  // Generation log
}
```

**Example files:**
```
library_r1.predicted.speclib    # Binary spectral library
library_r1.tsv                  # TSV version (if generated)
library_generation.log          # DIANN output log
```

### Module: TUNE_MODELS

**Location:** `results/tuning/`

**Outputs:**
```groovy
process TUNE_MODELS {
    publishDir "${params.outdir}/tuning"

    output:
    path "out-lib.dict.txt", emit: tokens                     // Tokenization dictionary
    path "out-lib.tuned_rt.pt", emit: rt_model, optional: true // RT model
    path "out-lib.tuned_im.pt", emit: im_model, optional: true // IM model
    path "out-lib.tuned_fr.pt", emit: fr_model, optional: true // FR model (2.3.1+)
    path "tune.log", emit: log                                // Tuning log
}
```

**Example files:**
```
out-lib.dict.txt         # ~100 KB  - Tokenization dictionary
out-lib.tuned_rt.pt      # ~5 MB    - Retention time model
out-lib.tuned_im.pt      # ~5 MB    - Ion mobility model
out-lib.tuned_fr.pt      # ~10 MB   - Fragment intensity model (if tune_fr: true)
tune.log                 # ~10 KB   - Tuning execution log
```

**Note:** The `.pt` files are PyTorch model files that get used as inputs to subsequent library generation.

### Module: QUANTIFY

**Location:** `results/{sample_id}/`

**Outputs:**
```groovy
process QUANTIFY {
    publishDir "${params.outdir}/${sample_id}"

    output:
    tuple val(sample_id), path("report.parquet"), emit: report        // Main results
    tuple val(sample_id), path("out-lib.parquet"), emit: out_lib      // Output library
    tuple val(sample_id), path("*.tsv"), emit: matrices, optional: true // Matrices
    path "diann.log", emit: log                                       // DIANN log
}
```

**Example files for one sample:**
```
report.parquet          # Main quantification results (precursor-level)
out-lib.parquet         # Empirical spectral library (used for tuning)
pg.matrix.tsv           # Protein group abundance matrix
pr.matrix.tsv           # Precursor abundance matrix
diann.log               # DIANN execution log
```

## Round-by-Round Breakdown

### After Round 1 Completes

```
results/
├── library/
│   ├── library_r1.predicted.speclib   ← Generated with default models
│   └── library_generation.log
│
├── mann/                              ← Quantified with R1 library
│   ├── report.parquet
│   ├── out-lib.parquet                ← This is used for tuning if tune_sample='mann'
│   └── diann.log
│
├── p2/
│   ├── report.parquet
│   ├── out-lib.parquet                ← This is used for tuning if tune_sample='p2'
│   └── diann.log
│
└── std/
    ├── report.parquet
    ├── out-lib.parquet
    └── diann.log
```

### After Tuning Completes

```
results/
├── library/
│   └── library_r1.predicted.speclib
│
├── tuning/                            ← NEW: Tuned models
│   ├── out-lib.dict.txt               ← Input for R2 library generation
│   ├── out-lib.tuned_rt.pt            ← Input for R2 library generation
│   ├── out-lib.tuned_im.pt            ← Input for R2 library generation
│   ├── out-lib.tuned_fr.pt            ← Input for R3 library generation
│   └── tune.log
│
├── mann/
│   └── ... (from R1)
├── p2/
│   └── ... (from R1)
└── std/
    └── ... (from R1)
```

**Key Point:** The tuning process takes `out-lib.parquet` from the `tune_sample` (e.g., `p2/out-lib.parquet`) and produces the tuned model files.

### After Round 2 Completes

```
results/
├── library/
│   ├── library_r1.predicted.speclib
│   ├── library_r2.predicted.speclib   ← NEW: Generated with RT+IM models
│   └── library_generation.log
│
├── tuning/
│   └── ... (tuned models)
│
├── mann/                              ← NEW: Quantified with R2 library
│   ├── report.parquet                 ← Updated with R2 results
│   ├── out-lib.parquet
│   └── diann.log
│
├── p2/                                ← NEW: Quantified with R2 library
│   └── ...
└── std/                               ← NEW: Quantified with R2 library
    └── ...
```

**Important:** In the current implementation, the sample directories get **overwritten** by each round. See "Current Behavior vs. Ideal Behavior" below.

### After Round 3 Completes

```
results/
├── library/
│   ├── library_r1.predicted.speclib
│   ├── library_r2.predicted.speclib
│   ├── library_r3.predicted.speclib   ← NEW: Generated with RT+IM+FR models
│   └── library_generation.log
│
├── tuning/
│   └── ... (all tuned models)
│
├── mann/                              ← FINAL: Quantified with R3 library
│   ├── report.parquet                 ← Final results
│   ├── out-lib.parquet
│   └── diann.log
│
├── p2/
│   └── ... (final results)
└── std/
    └── ... (final results)
```

## Current Behavior vs. Ideal Behavior

### ⚠️ Current Behavior

The current workflow **overwrites** sample results in each round because `publishDir` uses `mode: 'copy', overwrite: true`.

**Issue:** You only get the final round's results in each sample directory.

### ✅ Better Approach (Recommended)

Modify the workflow to separate results by round:

```
results/
├── library/
│   ├── library_r1.predicted.speclib
│   ├── library_r2.predicted.speclib
│   └── library_r3.predicted.speclib
│
├── tuning/
│   └── ...
│
├── r1/                                # Round 1 results
│   ├── mann/
│   ├── p2/
│   └── std/
│
├── r2/                                # Round 2 results
│   ├── mann/
│   ├── p2/
│   └── std/
│
└── r3/                                # Round 3 results (FINAL)
    ├── mann/
    ├── p2/
    └── std/
```

## How to Implement Round-Specific Output Directories

### Option 1: Modify full_pipeline.nf (Quick Fix)

Change the `publishDir` dynamically per round:

```groovy
// In full_pipeline.nf

// Round 1
QUANTIFY(
    samples_r1_ch,
    GENERATE_LIBRARY.out.library,
    fasta_file
).set { r1_results }

// Then override publishDir
r1_results.report.subscribe { sample_id, file ->
    file.copyTo("${params.outdir}/r1/${sample_id}/report.parquet")
}

// Round 2
QUANTIFY(
    samples_r2_ch,
    GENERATE_LIBRARY.out.library,
    fasta_file
).set { r2_results }

// And so on...
```

### Option 2: Modify quantify.nf Module (Better)

Make the module accept a round parameter:

```groovy
// modules/quantify.nf
process QUANTIFY {
    label 'diann_quantify'
    publishDir "${params.outdir}/${round}/${sample_id}", mode: 'copy', overwrite: true

    tag "$sample_id (${round})"

    input:
    tuple val(sample_id), path(ms_dir), val(file_type), val(round)
    path library
    path fasta

    // ... rest of process
}
```

Then call with round information:

```groovy
// In full_pipeline.nf

// Round 1
samples_r1_ch = Channel.fromList(samples_list)
    .map { sample ->
        tuple(
            sample.id,
            file(sample.dir),
            sample.file_type ?: 'raw',
            'r1'  // Round identifier
        )
    }
```

## File Sizes (Approximate)

Typical file sizes for a 3-sample, 3-round pipeline:

```
Library files:
  library_r1.predicted.speclib     ~500 MB
  library_r2.predicted.speclib     ~500 MB
  library_r3.predicted.speclib     ~500 MB

Tuned models:
  out-lib.dict.txt                 ~100 KB
  out-lib.tuned_rt.pt              ~5 MB
  out-lib.tuned_im.pt              ~5 MB
  out-lib.tuned_fr.pt              ~10 MB

Per-sample results (each):
  report.parquet                   ~50-200 MB (depends on data)
  out-lib.parquet                  ~100-500 MB
  pg.matrix.tsv                    ~1-10 MB
  pr.matrix.tsv                    ~5-50 MB
  diann.log                        ~1 MB

Total for 3 samples, 3 rounds:     ~3-10 GB
```

## Accessing Specific Outputs

### Get Final Quantification Results

```bash
# Final results (from R3)
results/mann/report.parquet
results/p2/report.parquet
results/std/report.parquet
```

### Get Tuned Models (for reuse)

```bash
# Copy tuned models for use in other projects
cp results/tuning/out-lib.dict.txt /path/to/shared/models/
cp results/tuning/out-lib.tuned_rt.pt /path/to/shared/models/
cp results/tuning/out-lib.tuned_im.pt /path/to/shared/models/
cp results/tuning/out-lib.tuned_fr.pt /path/to/shared/models/
```

### Get Libraries for Reuse

```bash
# Use the final tuned library for other samples
cp results/library/library_r3.predicted.speclib /path/to/shared/libraries/

# Then use with quantify_only.nf:
nextflow run karlssoc/diann-wf \
  --library /path/to/shared/libraries/library_r3.predicted.speclib \
  --fasta mydata.fasta \
  --samples '[{"id":"new_sample","dir":"input/new","file_type":"d"}]' \
  -profile slurm
```

## Nextflow Work Directory

In addition to the published results, Nextflow maintains a work directory:

```
work/
├── 12/
│   └── 3abc...def/                    # GENERATE_LIBRARY task
│       ├── library_r1.predicted.speclib
│       └── ... (temporary files)
├── 34/
│   └── 5ghi...jkl/                    # TUNE_MODELS task
│       └── ... (temporary files)
└── 56/
    └── 7mno...pqr/                    # QUANTIFY task for sample 1
        └── ... (temporary files)
```

**Note:** The `work/` directory can be safely deleted after the pipeline completes successfully, as all important outputs are copied to `results/`.

## Cleaning Up

After successful completion:

```bash
# Keep only published results
rm -rf work/

# Or use Nextflow's clean command
nextflow clean -f

# Keep execution reports but remove work files
nextflow clean -k
```

## Summary: Key Output Locations

| What | Where | Used For |
|------|-------|----------|
| **Libraries** | `results/library/*.speclib` | Reuse for other samples, future projects |
| **Tuned Models** | `results/tuning/*.pt` | Reuse for creating new libraries |
| **Final Results** | `results/{sample}/report.parquet` | Data analysis, downstream processing |
| **Matrices** | `results/{sample}/*.tsv` | Statistical analysis, plotting |
| **Logs** | `results/{sample}/diann.log` | Troubleshooting, parameter verification |
| **Pipeline Reports** | `results/pipeline_info/` | Performance analysis, optimization |

## Recommendation

For production use, I recommend modifying the workflow to output results by round (r1/, r2/, r3/) to preserve all intermediate results. This makes it easier to:
- Compare results across rounds
- Troubleshoot issues
- Decide which round's results to use for analysis

Would you like me to create an updated version of `full_pipeline.nf` that implements round-specific output directories?
