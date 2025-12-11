# Generic Output Organization Design

The workflow modules now support **generic, flexible output organization** without hard-coding specific use cases.

## Core Design Principle

All modules accept an optional `subdir` parameter that controls where outputs are published:

```groovy
publishDir "${params.outdir}${subdir ? '/' + subdir : ''}/${sample_id}"
```

This means:
- **If `subdir = ''`** → `outdir/sample_id/`
- **If `subdir = 'stage1'`** → `outdir/stage1/sample_id/`
- **If `subdir = 'baseline/replicate_a'`** → `outdir/baseline/replicate_a/sample_id/`

## Module Signatures

### QUANTIFY
```groovy
input:
tuple val(sample_id), path(ms_dir), val(file_type), val(subdir)
path library
path fasta
```

### GENERATE_LIBRARY
```groovy
input:
path fasta
val library_name
val subdir
path tokens, stageAs: 'tokens.txt'
path rt_model, stageAs: 'rt_model.pt'
path im_model, stageAs: 'im_model.pt'
path fr_model, stageAs: 'fr_model.pt'
```

###TUNE_MODELS
```groovy
input:
path library
val tune_name
val subdir
```

## Usage Patterns

### Pattern 1: Simple Workflow (No Subdirectories)

```groovy
// quantify_only.nf
def subdir = params.subdir ?: ''  // Default to no subdirectory

samples_ch = Channel.fromList(samples_list)
    .map { sample -> tuple(sample.id, file(sample.dir), sample.file_type, subdir) }

QUANTIFY(samples_ch, library, fasta)
```

**Result:** `results/sample1/`, `results/sample2/`

### Pattern 2: Organized by Stage

```groovy
// full_pipeline.nf
def stage_name = 'stage1'

samples_ch = Channel.fromList(samples_list)
    .map { sample -> tuple(sample.id, file(sample.dir), sample.file_type, stage_name) }

QUANTIFY(samples_ch, library, fasta)
```

**Result:** `results/stage1/sample1/`, `results/stage1/sample2/`

### Pattern 3: Custom Organization

```groovy
// Custom workflow
def organization = params.batch_name ? "batch_${params.batch_name}" : 'default'

samples_ch = Channel.fromList(samples_list)
    .map { sample -> tuple(sample.id, file(sample.dir), sample.file_type, organization) }

QUANTIFY(samples_ch, library, fasta)
```

**Result:** `results/batch_20241210/sample1/`, `results/batch_20241210/sample2/`

### Pattern 4: Nested Organization

```groovy
// Organize by experiment and condition
samples_ch = Channel.fromList(samples_list)
    .map { sample ->
        def subdir = "${params.experiment}/${sample.condition}"
        tuple(sample.id, file(sample.dir), sample.file_type, subdir)
    }

QUANTIFY(samples_ch, library, fasta)
```

**Result:** `results/exp001/control/sample1/`, `results/exp001/treated/sample2/`

## Full Pipeline Configuration

The `full_pipeline.nf` supports two organization strategies:

### Strategy 1: By Stage (Default)

```yaml
output_organization: 'by_stage'
stages: [1, 2, 3]
```

**Result:**
```
results/
├── stage1/
│   ├── library/
│   ├── mann/
│   ├── p2/
│   └── std/
├── stage2/
│   ├── library/
│   ├── mann/
│   ├── p2/
│   └── std/
├── stage3/
│   ├── library/
│   ├── mann/
│   ├── p2/
│   └── std/
└── tuning/
```

### Strategy 2: Flat (All in Root)

```yaml
output_organization: 'flat'
stages: [1, 2, 3]
```

**Result:**
```
results/
├── library/
│   ├── library_stage1.predicted.speclib
│   ├── library_stage2.predicted.speclib
│   └── library_stage3.predicted.speclib
├── tuning/
├── mann/         # ⚠️ Overwritten by each stage
├── p2/           # ⚠️ Overwritten by each stage
└── std/          # ⚠️ Overwritten by each stage
```

### Strategy 3: Custom Stage Names

```yaml
output_organization: 'by_stage'
stages: [1, 2, 3]
stage_names:
  1: 'baseline'
  2: 'rt_im_optimized'
  3: 'full_optimized'
```

**Result:**
```
results/
├── baseline/
│   ├── library/
│   └── {samples}/
├── rt_im_optimized/
│   ├── library/
│   └── {samples}/
├── full_optimized/
│   ├── library/
│   └── {samples}/
└── tuning/
```

## Advanced: Dynamic Stage Configuration

You can fully customize each stage:

```yaml
stages: [1, 2, 3, 4]  # Run 4 stages
tune_after_stage: 2    # Tune after stage 2

stage_names:
  1: 'initial'
  2: 'replicate1'
  3: 'tuned_basic'
  4: 'tuned_advanced'

stage_configs:
  1:
    diann_version: '2.2.0'
    library_name: 'lib_initial'
    use_tuned_models: false
  2:
    diann_version: '2.2.0'
    library_name: 'lib_replicate'
    use_tuned_models: false
  3:
    diann_version: '2.3.1'
    library_name: 'lib_rt_im'
    use_tuned_models: true
    use_fr_model: false
  4:
    diann_version: '2.3.1'
    library_name: 'lib_full'
    use_tuned_models: true
    use_fr_model: true
```

**Result:**
```
results/
├── initial/
│   ├── library/
│   │   └── lib_initial.predicted.speclib
│   └── {samples}/
├── replicate1/
│   ├── library/
│   │   └── lib_replicate.predicted.speclib
│   └── {samples}/
├── tuning/              # Created after stage 2
│   └── tuned_models.*
├── tuned_basic/
│   ├── library/
│   │   └── lib_rt_im.predicted.speclib  (uses RT+IM models)
│   └── {samples}/
└── tuned_advanced/
    ├── library/
    │   └── lib_full.predicted.speclib   (uses RT+IM+FR models)
    └── {samples}/
```

## Benefits of This Approach

### 1. **Not Use-Case Specific**
The modules don't know about "rounds", "stages", "batches", or "experiments". They just organize by `subdir`.

### 2. **Fully Flexible**
Users can organize outputs however they want:
- By processing round (stage1, stage2, stage3)
- By experiment (exp_A, exp_B, exp_C)
- By date (2024-12-10, 2024-12-11)
- By condition (control, treated_low, treated_high)
- Nested (batch1/control, batch1/treated, batch2/control)

### 3. **Backward Compatible**
Simple workflows can pass empty string (`''`) and get the original flat behavior.

### 4. **Future-Proof**
New organization patterns can be added without changing module code.

## Example: Alternative Use Cases

### Use Case: Batch Processing

```groovy
// Process multiple batches with different libraries
batches.each { batch ->
    samples_ch = Channel.fromList(batch.samples)
        .map { sample ->
            tuple(sample.id, file(sample.dir), sample.file_type, batch.name)
        }

    QUANTIFY(samples_ch, file(batch.library), fasta)
}

// Results:
// results/batch_2024_11/sample1/
// results/batch_2024_12/sample1/
```

### Use Case: Condition Comparison

```groovy
// Compare different experimental conditions
conditions = ['control', 'treatment_A', 'treatment_B']

conditions.each { condition ->
    samples_ch = condition_samples[condition]
        .map { sample ->
            tuple(sample.id, file(sample.dir), sample.file_type, condition)
        }

    QUANTIFY(samples_ch, library, fasta)
}

// Results:
// results/control/rep1/
// results/control/rep2/
// results/treatment_A/rep1/
// results/treatment_A/rep2/
// results/treatment_B/rep1/
// results/treatment_B/rep2/
```

### Use Case: Time Series

```groovy
// Organize by timepoint
timepoints = ['T0', 'T1h', 'T4h', 'T24h']

timepoints.each { tp ->
    samples_ch = timepoint_samples[tp]
        .map { sample ->
            tuple(sample.id, file(sample.dir), sample.file_type, "timeseries/${tp}")
        }

    QUANTIFY(samples_ch, library, fasta)
}

// Results:
// results/timeseries/T0/sample1/
// results/timeseries/T1h/sample1/
// results/timeseries/T4h/sample1/
// results/timeseries/T24h/sample1/
```

## Migration from Old Workflow

Old approach (hard-coded):
```groovy
publishDir "${params.outdir}/${sample_id}"  // Fixed structure
```

New approach (flexible):
```groovy
publishDir "${params.outdir}${subdir ? '/' + subdir : ''}/${sample_id}"  // Dynamic

// Backward compatible:
def subdir = ''  // Gives same result as old approach
```

## Summary

**Key Innovation:** The `subdir` parameter is:
- ✅ Generic (no assumptions about use case)
- ✅ Optional (defaults to empty string)
- ✅ Flexible (can be any directory path)
- ✅ Composable (can nest subdirectories)
- ✅ Backward compatible (empty string = original behavior)

This allows the same modules to support:
- Simple flat workflows
- Multi-stage pipelines
- Batch processing
- Condition comparisons
- Time series
- Any future organizational pattern

**The workflow doesn't dictate structure—it enables structure.**
