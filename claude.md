# DIA-NN Nextflow Workflow - AI Assistant Guide

This document provides context for AI assistants (like Claude) working on this project.

## Project Overview

A Nextflow DSL2 workflow for DIA-NN (Data-Independent Acquisition by Neural Networks) mass spectrometry analysis. The workflow supports library generation, model tuning, and sample quantification with SLURM HPC integration.

**Key Technology Stack:**
- **Nextflow** (DSL2) - Workflow orchestration
- **DIA-NN 2.3.2** - MS analysis tool (runs in Singularity containers)
- **SLURM** - HPC job scheduler
- **Singularity/Apptainer** - Container runtime

## Project Structure

```
diann-wf/
├── main.nf                 # Single entry point for all workflows (use -entry flag)
│
├── workflows/              # Workflow definitions
│   ├── quantify_fasta_subset.nf         # PRODUCTION: Full FASTA quant -> subset FASTA -> quantify all
│   ├── quantify_fasta_subset_by_biospe.nf # PRODUCTION: Same, per-biospecimen FASTA subset
│   ├── presearch_and_quantify.nf        # PRODUCTION: Presearch N files -> subset library -> quantify all
│   ├── library_and_quantify.nf          # PRODUCTION: Generate library + quantify
│   ├── iterative_quant.nf               # DEVELOPMENT: Iterative quant with calibration
│   ├── quantify_only.nf                 # Quantify with existing library
│   ├── create_library.nf                # Generate spectral library
│   ├── convert_library.nf               # Convert .speclib to .parquet
│   ├── tune_only.nf                     # Tune prediction models
│   ├── repredict_library.nf             # Repredict library from existing
│   ├── infindia_presearch_only.nf       # Library-free presearch
│   ├── compare_libraries.nf             # Compare default vs tuned libraries
│   ├── compare_with_models.nf           # Compare default vs preset models
│   └── evaluate_models.nf               # Multi-preset accuracy comparison
│
├── modules/                # Reusable process modules
│   ├── library.nf              # GENERATE_LIBRARY
│   ├── tune.nf                 # TUNE_MODELS
│   ├── quantify.nf             # QUANTIFY
│   ├── convert_library.nf      # CONVERT_LIBRARY
│   ├── convert_to_dia.nf       # CONVERT_TO_DIA, CONVERT_TO_DIA_BATCH
│   ├── infindia_presearch.nf   # INFINDIA_PRESEARCH
│   ├── repredict_library.nf    # REPREDICT_LIBRARY
│   ├── subset_library.nf       # SUBSET_LIBRARY (by Protein.Group)
│   ├── subset_library_peptide.nf # SUBSET_LIBRARY_PEPTIDE (by Modified.Sequence)
│   ├── subset_fasta.nf         # SUBSET_FASTA (filter FASTA to detected proteins)
│   ├── extract_sequences.nf    # EXTRACT_SEQUENCES
│   ├── filter_library.nf       # FILTER_LIBRARY_CHARGE
│   ├── compare_matrices.nf     # COMPARE_MATRICES (DuckDB pg_matrix comparison)
│   └── model_accuracy_report.nf # MODEL_ACCURACY_REPORT
│
├── bin/                    # Utility scripts
│   ├── diann-wf                # Wrapper script (abstracts Nextflow for users)
│   ├── compare_pg_matrices.py  # Standalone pg_matrix comparison CLI (DuckDB)
│   ├── extract_metrics.py      # Extract metrics from DIA-NN reports
│   ├── collect_models.sh       # Organize tuning outputs into model presets
│   └── ...
│
├── lib/                    # Shared Nextflow utility functions
│   ├── samples.nf             # parseSamples(), createSamplesChannel()
│   ├── models.nf              # resolveModelFiles(), logModelInfo()
│   └── files.nf               # countMSFiles()
│
├── configs/                # Configuration templates
│   ├── workflows/             # Multi-module workflows
│   ├── quantify/              # Single module configs
│   ├── library/               # Library generation configs
│   ├── tune/                  # Model tuning configs
│   ├── presearch/             # Presearch configs
│   ├── test/                  # Test configurations
│   └── cosmos/                # COSMOS HPC examples
│
├── models/                 # Pre-trained model presets
│
└── nextflow.config         # Main configuration (profiles, resources, param defaults)
```

## Core Concepts

### 1. Nextflow Channels
**CRITICAL CHANNEL ISSUES TO WATCH:**
- **Queue channels** consume items (one process reads, channel is empty)
- **Value channels** broadcast items (multiple processes can use same value)
- Process outputs are queue channels by default
- Use `.first()` to convert queue → value channel for broadcasting
- **Bug history**: `tuned_library` needed `.first()` to broadcast to all samples

### 2. Process Labels
Resources are allocated via labels in `nextflow.config`:
- `diann_tune`: 10 CPUs, 10 GB RAM, 2h
- `diann_library`: 30-60 CPUs (parallel mode dependent), 20-30 GB, 4h
- `diann_quantify`: 30-60 CPUs (parallel mode dependent), dynamic RAM, dynamic time
- `diann_convert`: 10 CPUs, 10 GB RAM, 1h

### 3. SLURM Configuration
**Critical settings (nextflow.config):**
```groovy
executor {
    exitReadTimeout = '4 min'  // MUST be < MinJobAge (5min on kraken)
    pollInterval = '15 sec'
    queueStatInterval = '1 min'
}
```

**Why 4 minutes?** kraken's `MinJobAge = 300 sec` means SLURM purges job records after 5 minutes. Nextflow must read exit status before purge.

### 4. Parallel Execution Mode
`parallel_mode = true` in YAML:
- Splits 60-core jobs into 2x 30-core jobs
- Better throughput, allows concurrent sample processing
- `maxForks = 2` prevents >60 core usage

## Common Issues & Solutions

### Issue 1: "Terminated for unknown reason"
**Cause:** SLURM `exitReadTimeout` exceeds `MinJobAge`
**Solution:** Set `exitReadTimeout < 5 min` (currently 4 min)

### Issue 2: Tuned models not applied
**Cause:** Groovy boolean → bash string conversion
**Solution:** Explicit string conversion: `(condition) ? 'true' : 'false'`

### Issue 3: Multi-sample quantification missing samples
**Cause:** Channel not broadcasting to all samples
**Solution:** Use `.first()` on library channel to convert to value channel

### Issue 4: Parallel jobs interfering
**Cause:** DIA-NN writes `.quant` files to input directory
**Solution:** Use `--temp temp_diann` flag (implemented in quantify.nf)

### Issue 5: "Cannot coerce map to Integer"
**Cause:** Using closures `{ }` for config directives that need direct evaluation
**Solution:** Remove closures, use direct ternary: `params.parallel_mode ? 30 : 60`

### Issue 6: CONVERT_TO_DIA fails with symlinked RAW files
**Cause:** DIA-NN's `--convert` flag cannot read Thermo RAW files that are symlinks
**Symptom:** Conversion silently fails or produces no output when input files are symbolic links
**Solution:** Use real files, not symlinks. Nextflow staging typically creates symlinks by default - ensure the process receives actual files or configure staging to copy files instead.
**Note:** This is a DIA-NN limitation, not a Nextflow issue.

### Issue 7: INFINDIA_PRESEARCH fails with Thermo RAW and Bruker .d files
**Cause:** DIA-NN's InfinDIA pre-search cannot read Thermo RAW or Bruker .d files directly
**Symptom:** Pre-search fails with `ERROR: cannot open the raw data folder` or produces no results
**Solution:** Convert RAW/.d files to .dia format before running INFINDIA_PRESEARCH. mzML files can be used directly without conversion.
**Implementation:** Use `convert_to_dia: true` in config. The iterative_quant and infindia_presearch_only workflows automatically convert files to .dia before presearch.

### Issue 8: DIA-NN hangs at "Loading run" with Bruker .d files — stale `/dev/shm/bip.gmem.map*`
**Cause:** DIA-NN's Bruker TDF reading library uses a shared memory file (`/dev/shm/bip.gmem.map.41_0.000000`) for IPC. When a Nextflow run is cancelled while DIA-NN is processing `.d` files, this file is left orphaned in `/dev/shm/`. The next DIA-NN process opens the stale file and waits indefinitely for a server response that never comes.
**Symptom:** DIA-NN prints `[0:xx] Loading run <file>.d` then stops. Process is alive (visible in `ps aux`) with 60 threads all in `hrtimer_nanosleep` state, zero I/O activity (`/proc/PID/io` empty), and only 5 open file descriptors including `/dev/shm/bip.gmem.map.41_0.000000`.
**Diagnosis:** `ls -la /dev/shm/bip.gmem.map*` — if timestamp predates current run, it's stale.
**Solution:** Kill the DIA-NN process and delete the stale file:
```bash
kill -9 <diann_pid>
rm -f /dev/shm/bip.gmem.map*
```
Then resubmit (Nextflow will retry automatically, or use `-resume`).
**Prevention:** Add the following to project launch scripts before `nextflow run`:
```bash
rm -f /dev/shm/bip.gmem.map* 2>/dev/null
```
**Note:** Only affects Bruker `.d` (timsTOF) files. Triggered by any cancelled Nextflow run that left DIA-NN mid-processing. Accumulates across multiple cancellations on the same node.

## Important Patterns

### DIA-NN Binary Path (Runtime Resolution)
`params.diann_binary` is `null` in nextflow.config. Modules compute the path at runtime:
```groovy
def diann_cmd = params.diann_binary ?: "/usr/bin/diann-${params.diann_version}/diann-linux"
```
**Why?** GString interpolation in `nextflow.config` params block evaluates at parse time,
before YAML overrides are applied. Setting `diann_binary` to a GString there would lock in
the default `diann_version` and ignore YAML overrides.

### Dynamic CPU Allocation
Modules use `${task.cpus}` (NOT `${params.threads}`):
```bash
diann --threads ${task.cpus}  # Correct
diann --threads ${params.threads}  # Wrong in parallel mode
```

### Boolean to Bash String
```groovy
def use_tuned = (condition) ? 'true' : 'false'  # Correct
def use_tuned = condition  # Wrong - becomes groovy boolean
```

### Channel Broadcasting
```groovy
// Wrong - channel consumed by first sample
QUANTIFY(samples_ch, library, ...)

// Wrong - .first() inline produces Nextflow WARN
QUANTIFY(samples_ch, GENERATE_LIBRARY.out.library.first(), ...)

// Correct - convert at assignment time, then use variable
def generated_library = GENERATE_LIBRARY.out.library.first()
QUANTIFY(samples_ch, generated_library, ...)
```

### Optional File Outputs
Use placeholders to prevent missing file errors:
```groovy
output:
path "out.txt", emit: result, optional: true
```

## Git Commit Message Format

Follow this format (enforced in project):
```
<type>: <subject line>

<body explaining what and why>

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
```

## Testing Strategy

### Critical Testing Principles

1. **Successful execution ≠ correct output**: A workflow completing with exit code 0 does not mean results are valid. Always verify output content matches the intended behavior (e.g., expected ID rates, file sizes, column counts).

2. **Always analyze log files**: Tool-specific logs (e.g., `diann.log`, `report.log.txt`) contain warnings and metrics that are essential for validation. New warnings must be understood before concluding a test passed.

3. **Compare metrics, not just existence**: Check that quantitative outputs (protein counts, precursor IDs, reduction percentages) match expectations, not just that files were created.

**Local testing (standard profile):**
```bash
nextflow run karlssoc/diann-wf -entry quantify_only \
  -params-file configs/quantify/basic.yaml \
  -profile standard
```

**SLURM testing:**
```bash
nextflow -bg run karlssoc/diann-wf -entry quantify_only \
  -params-file configs/quantify/basic.yaml \
  -profile slurm
```

**Using the wrapper script:**
```bash
diann-wf quantify_only configs/quantify/basic.yaml slurm
```

**Key test cases:**
1. Single sample quantification
2. Multi-sample quantification (tests channel broadcasting)
3. Parallel mode (tests maxForks, resource allocation)
4. Resume capability (`-resume`)

## File Naming Conventions

**Workflows:** `<action>_<scope>.nf`
- `quantify_only.nf`, `create_library.nf`, `compare_libraries.nf`

**Modules:** `<function>.nf`
- `library.nf`, `tune.nf`, `quantify.nf`

**Configs:** `configs/<category>/<variant>.yaml`
- `configs/quantify/basic.yaml`
- `configs/workflows/compare_libraries.yaml`

## Current Known Limitations

1. **sacct not available** on kraken - cannot query job history
2. **Graphviz not installed** - DAG visualization unavailable
3. **SLURM accounting database issues** - connection refused errors
4. **Node-specific allocation** - Currently hardcoded to `alap759` for stability

## Recent Major Fixes (Dec 2025)

1. ✅ SLURM timeout configuration (exitReadTimeout 10min → 4min)
2. ✅ Standard profile CPU allocation (was using 1 thread)
3. ✅ Parallel quantification interference (--temp flag)
4. ✅ Closure syntax in config directives
5. ✅ Multi-sample channel broadcasting
6. ✅ Config reorganization (workflows/ vs modules/)

## Recent Major Fixes (Feb 2026)

1. ✅ `diann_binary` GString self-reference bug (all 7 modules use runtime fallback)
2. ✅ Undefined params warnings (all params declared in nextflow.config)
3. ✅ `.first()` warnings (moved to assignment time in production workflows)
4. ✅ `individual_mass_acc` default changed to `false` (was causing ~12% systematic intensity decrease)
5. ✅ All configs/docs updated for `nextflow pull` compatibility (`-entry` syntax)
6. ✅ New entry points: `convert_library`, `tune_models` in main.nf
7. ✅ Wrapper script `bin/diann-wf` for non-Nextflow users
8. ✅ Restructured workflows: removed broken `full_pipeline.nf`, `compare_library_tuning.nf`, `evaluate_methods.nf` (14 → 11 workflows)
9. ✅ Sanity comparison tool: `bin/compare_pg_matrices.py` + `modules/compare_matrices.nf`

## Recent Major Changes (Mar 2026)

1. ✅ New workflow: `QUANTIFY_FASTA_SUBSET` — full FASTA quant → subset FASTA → fresh speclib → quantify all (now recommended over PRESEARCH_AND_QUANTIFY)
2. ✅ New workflow: `QUANTIFY_FASTA_SUBSET_BY_BIOSPE` — same with per-biospecimen FASTA subsetting (plasma/CSF/etc.)
3. ✅ Output structure standardised: stage-named subdirs throughout (`quant_full/`, `quant_subset/`, `quantification/`)
4. ✅ `QUANTIFY_FASTA_SUBSET`: renamed `samples` → `batches` parameter; pass1/flat → `quant_full`/`quant_subset` subdirs (avoids confusion with DIA-NN's `report-first-pass.*` naming)
5. ✅ `PRESEARCH_AND_QUANTIFY`: fixed presearch double-nesting (`presearch/presearch/` → `presearch/`); final results moved to `quantification/<sample>/`

## Development Guidelines

1. **Always test both profiles** (standard + slurm)
2. **Test with multiple samples** (catches channel issues)
3. **Check both sequential and parallel modes**
4. **Use `nextflow lint .` before committing**
5. **Read files before editing** (Edit tool requirement)
6. **Test resume capability** after workflow changes

## Useful Nextflow Commands

```bash
# Run in background
nextflow -bg run <workflow> ...

# Resume failed run
nextflow run <workflow> -resume ...

# Clean work directories
nextflow clean -f

# View run history
nextflow log

# Pull latest from GitHub
nextflow pull karlssoc/diann-wf

# Lint check
nextflow lint .
```

## Environment-Specific Details

**kraken (Lab Server):**
- OS: Linux (Darwin 25.1.0)
- SLURM MinJobAge: 5 minutes
- Total cores: 192
- Working node: alap759 (60 cores)
- Singularity cache: `/home/karlssoc/.singularity/cache/`
- User account: `karlssoc`
- Partition: `work` (default)
- **Note:** This is a dedicated lab server, not a shared HPC cluster

**COSMOS HPC (LUNARC):**
- URL: https://www.lunarc.lu.se/systems/cosmos
- Node config: AMD Milan (2×24 cores = 48 cores per node)
- Memory: 256 GB per node (5.3 GB per core)
- Local disk: 2 TB per node at `$SNIC_TMP`
- Storage: `/lunarc/nobackup/projects/`
- Interconnect: HDR InfiniBand (100 Gbit/node)
- Queueing: SLURM
- Container: Singularity/Apptainer
- Default partition: `lu`
- **Profile:** Use `-profile cosmos` for optimized execution

**COSMOS Profile Optimizations:**
- Automatic thread limit: 48 cores (matches node capacity)
- Local disk staging via `scratch = '$SNIC_TMP'` for:
  - QUANTIFY process (massive I/O improvement for MS files)
  - TUNE_MODELS process (improves library reading)
- Parallel mode: 2×24 cores (better throughput for multiple samples)
- No node pinning (shared cluster environment)
- SLURM timeout tuning for shared cluster

## Execution Profiles Summary

| Profile | Environment | Cores | Container | Local Disk | Use Case |
|---------|------------|-------|-----------|------------|----------|
| `standard` | Local | Variable | Singularity | No | Development/testing |
| `slurm` | Generic HPC | 60 (default) | Singularity | No | Lab server (kraken) |
| **`cosmos`** | LUNARC HPC | 48 (fixed) | Singularity | Yes ($SNIC_TMP) | **Production on COSMOS** |
| `docker` | Local | Variable | Docker | No | macOS development |
| `docker_slurm` | Generic HPC | Variable | Docker | No | HPC with Docker |

## Key Parameters Reference

### Common Across All Workflows
- `diann_version`: DIA-NN version (default: 2.3.2)
- `threads`: CPU cores per job (default: 60)
- `outdir`: Output directory
- `slurm_account`: SLURM account name
- `slurm_queue`: SLURM partition (e.g., 'work')
- `slurm_nodelist`: Specific node (e.g., 'alap759')
- `parallel_mode`: Split jobs for concurrent execution (default: false)

### Quantification Specific
- `library`: Path to spectral library (.predicted.speclib or .parquet)
- `fasta`: Path to FASTA file
- `samples`: List of sample definitions (id, dir, file_type, recursive)
- `qvalue`: Precursor q-value threshold (0 = DIA-NN default 0.01)
- `pg_level`: Protein group level (1=proteins, 0=genes)
- `mass_acc_cal`: Mass accuracy calibration threshold
- `smart_profiling`: Use smart profiling (default: false)
- `individual_mass_acc`: Per-file mass accuracy (default: false, causes ~12% intensity decrease)
- `matrices`: Generate result matrices (default: true)
- `mbr`: Match-between-runs for identification stage (default: false)
- `mbr_final`: Match-between-runs for final quantification (default: true)
- `ultrafast`: Enable ultrafast mode (reduced accuracy, faster)

### Library Generation Specific
- `min_fr_mz`, `max_fr_mz`: Fragment m/z range
- `min_pep_len`, `max_pep_len`: Peptide length range
- `min_pr_mz`, `max_pr_mz`: Precursor m/z range
- `min_pr_charge`, `max_pr_charge`: Precursor charge range
- `cut`: Enzyme cleavage sites (e.g., 'K*,R*')
- `missed_cleavages`: Number allowed
- `met_excision`: Methionine excision (default: true)
- `unimod4`: Enable unimod4 modifications (default: true)

### Tuning Specific
- `tune_rt`: Tune retention time model (default: true)
- `tune_im`: Tune ion mobility model (default: false)
- `tune_fr`: Tune fragmentation model (default: true, requires 2.3.1+)

## Entry Points (main.nf -entry)

All workflows are accessible via `nextflow run karlssoc/diann-wf -entry <NAME>`:

| Entry | Type | Description |
|-------|------|-------------|
| `QUANTIFY_FASTA_SUBSET` | Production | Full FASTA quant → subset FASTA → fresh speclib → quantify all **(recommended)** |
| `QUANTIFY_FASTA_SUBSET_BY_BIOSPE` | Production | Same, but per-biospecimen FASTA subset (plasma, CSF, etc.) |
| `PRESEARCH_AND_QUANTIFY` | Production | Presearch N largest files → subset library parquet → quantify all |
| `LIBRARY_AND_QUANTIFY` | Production | Generate library + quantify (no search space reduction) |
| `create_library` | Standalone | Create spectral library from FASTA |
| `quantify_only` | Standalone | Quantify with existing library |
| `convert_library` | Standalone | Convert .speclib to .parquet |
| `tune_models` | Standalone | Tune prediction models |
| `ITERATIVE_QUANT` | Development | Iterative quantification (experimental) |

**Wrapper script** (`bin/diann-wf`) abstracts Nextflow for end users:
```bash
diann-wf QUANTIFY_FASTA_SUBSET config.yaml slurm                   # Production
diann-wf QUANTIFY_FASTA_SUBSET_BY_BIOSPE biospe_config.yaml slurm  # Per-biospecimen
diann-wf quantify_only quant.yaml docker -resume                   # With extra args
diann-wf list                                                       # Show all workflows
```

**Workflows NOT in main.nf** (run directly for development/comparison):
- `compare_libraries.nf`, `compare_with_models.nf`, `evaluate_models.nf`
- `infindia_presearch_only.nf`, `repredict_library.nf`, `tune_only.nf`

## Design Patterns

### Generic Output Organization with `subdir` Parameter

All modules support flexible output organization via an optional `subdir` parameter:

```groovy
publishDir "${params.outdir}${subdir ? '/' + subdir : ''}/${sample_id}"
```

**Examples:**
- `subdir = ''` → `outdir/sample_id/`
- `subdir = 'stage1'` → `outdir/stage1/sample_id/`
- `subdir = 'quant/default'` → `outdir/quant/default/sample_id/`

**Module signatures with subdir:**

```groovy
// QUANTIFY (6-element tuple + 5 separate inputs)
input:
tuple val(sample_id), path(ms_dir), val(file_type), val(subdir), val(recursive), val(file_count)
path library
path fasta
path ref_library
val mbr
val qvalue

// GENERATE_LIBRARY
input:
val subdir

// TUNE_MODELS
input:
val subdir
```

**Benefits:**
- Not use-case specific (modules don't know about "rounds", "stages", "batches")
- Fully flexible organization (by stage, experiment, date, condition, nested paths)
- Backward compatible (empty string = flat structure)
- Future-proof (new organization patterns don't require module changes)

**Usage patterns:**
```groovy
// Simple workflow - no subdirectories
def subdir = ''

// Organize by stage
def subdir = 'stage1'

// Custom organization
def subdir = "${params.experiment}/${sample.condition}"

// Biospe workflow: per-biospecimen subdirectory
def subdir = "${biospe_id}/quant_full"   // → outdir/plasma/quant_full/batch1/
```

**Standard output structures for production workflows:**
```
# QUANTIFY_FASTA_SUBSET
outdir/
├── library/                    # full FASTA library
├── quant_full/<batch_id>/      # full FASTA quantification (batches key)
├── subset_fasta/               # subset.fasta (union of all batches)
├── library/subset/             # fresh library from subset FASTA
└── quant_subset/<batch_id>/    # final quantification

# QUANTIFY_FASTA_SUBSET_BY_BIOSPE
outdir/
├── library/                             # full FASTA library (shared)
├── <biospe_id>/
│   ├── quant_full/<batch_id>/           # full FASTA quantification
│   ├── subset_fasta/                    # biospecimen-specific subset FASTA
│   ├── library/subset/                  # biospecimen-specific subset library
│   └── quant_subset/<batch_id>/         # final quantification
└── ...

# PRESEARCH_AND_QUANTIFY
outdir/
├── library/                    # generated speclib
├── presearch/                  # N-file presearch (single combined run)
├── subset_library/             # subsetted library parquet
└── quantification/<sample_id>/ # final quantification (samples key)
```

### Hierarchical Channel Pattern (biospe → batches)

Used in `QUANTIFY_FASTA_SUBSET_BY_BIOSPE` for per-biospecimen parallel processing without module changes.

**Re-keying via filename** — instead of adding a passthrough `val key` to modules, use the output filename as the key:
```groovy
// biospe_id used as output_name → plasma.fasta, csf.fasta
SUBSET_FASTA(pg_sources, fasta, subdir, biospe_id_ch)

// Re-key from baseName after async completion (order-independent)
def subset_fasta_keyed = SUBSET_FASTA.out.subset_fasta
    .map { fasta -> tuple(fasta.baseName, fasta) }
// → (plasma, path/to/plasma.fasta)
```

**`multiMap` to fork without double-consuming a queue channel:**
```groovy
def fork = biospe_reports.multiMap { biospe_id, reports ->
    pg_sources:   reports
    subdirs:      "${biospe_id}/subset_fasta"
    output_names: biospe_id
}
SUBSET_FASTA(fork.pg_sources, fasta, fork.subdirs, fork.output_names)
```

**`.join` to pair batches with their per-biospe library:**
```groovy
// final_batches_ch: (biospe_id, batch_id, ms_dir, ...)
// subset_lib_keyed: (biospe_id, library)
def final_joined = final_batches_ch.join(subset_lib_keyed, by: 0)
// → (biospe_id, batch_id, ms_dir, ..., library)

// Fork for process inputs (library is queue channel here, not value)
def final_fork = final_joined.multiMap { biospe_id, batch_id, ms_dir, file_type, subdir, recursive, file_count, library ->
    samples:   tuple(batch_id, ms_dir, file_type, subdir, recursive, file_count)
    libraries: library
}
QUANTIFY_FINAL(final_fork.samples, final_fork.libraries, ...)
```

**Why `libraries` is a queue channel (not `.first()`):** Each batch must get its own biospecimen's library. Using `.first()` would broadcast one library to all batches (wrong). The queue channel stays in sync because both forks share the same `final_joined` source.

### Pre-Trained Model Resolution

Pre-trained models are stored in `models/` and organized by instrument/LC/method combinations. The workflow supports flexible model resolution with a priority system.

**Directory structure:**
```
models/
├── README.md                    # User documentation
├── instrument_configs.yaml      # Index of available presets
├── ttht-evos-30spd/            # Example preset
│   ├── dict.txt                # Token dictionary
│   ├── tuned_rt.pt            # RT model
│   ├── tuned_im.pt            # IM model
│   ├── tuned_fr.pt            # FR model
│   └── metadata.yaml          # Provenance tracking
└── example-preset/             # Template for new presets
```

**Parameter resolution priority:**
1. **Explicit file paths** (`params.tokens`, `params.rt_model`, etc.) - highest priority
2. **Model preset** (`params.model_preset`) - if no explicit paths provided
3. **NO_FILE placeholder** - if neither preset nor paths provided (default models)

**Implementation pattern in workflows:**
```groovy
// Resolve model files from preset or explicit paths
def tokens_file = file('NO_FILE')
def rt_model_file = file('NO_FILE')
def im_model_file = file('NO_FILE')
def fr_model_file = file('NO_FILE')

// Tokens file - Priority 1: Explicit path
if (params.tokens) {
    tokens_file = file(params.tokens)
} else if (params.model_preset) {
    // Priority 2: Model preset
    def tokens_path = "${projectDir}/models/${params.model_preset}/dict.txt"
    if (file(tokens_path).exists()) {
        tokens_file = file(tokens_path)
        log.info "Using model preset: ${params.model_preset}"
    } else {
        log.warn "Model preset '${params.model_preset}' tokens not found at ${tokens_path}"
    }
}

// Repeat for rt_model, im_model, fr_model...

// Validate explicit paths exist
if (params.tokens && !tokens_file.exists()) {
    log.error "ERROR: Tokens file not found: ${params.tokens}"
    exit 1
}
```

**Usage in configs:**
```yaml
# Option 1: Use preset (recommended)
model_preset: 'ttht-evos-30spd'

# Option 2: Explicit paths (overrides preset)
tokens: 'path/to/dict.txt'
rt_model: 'path/to/tuned_rt.pt'
im_model: 'path/to/tuned_im.pt'
fr_model: 'path/to/tuned_fr.pt'
```

**Tuning modes:**
- `skip`: Use preset models directly (no TUNE_MODELS step) - fastest
- `from_preset`: Use preset as starting point for TUNE_MODELS (not yet implemented)
- `from_scratch`: Ignore preset, tune from DIA-NN defaults (current behavior, default)

**Collection script:**
Use `bin/collect_models.sh` to organize tuning outputs into repository structure:
```bash
./bin/collect_models.sh -s /path/to/tuning/output -n preset-name
```

**Model file handling:**
- Models are optional - use if available, fallback to defaults if missing
- Bash checks file existence: `if [ -s "rt_model.pt" ]; then RT_PARAM="--rt-model rt_model.pt"`
- Module signature unchanged (still accepts optional model files)

**Benefits:**
- Easy model reuse across projects (just specify preset name)
- Backward compatible (existing explicit paths still work)
- Self-documenting (metadata.yaml tracks provenance)
- Reproducible (models committed to Git)
- Flexible (can mix preset and explicit paths)

**Storage:**
- Models stored directly in Git (~9 MB per preset, <100 MB total for 10 presets)
- Will migrate to Git LFS if total size exceeds 100-150 MB

## Contact & Resources

- **Primary user:** karlssoc
- **Repository:** https://github.com/karlssoc/diann-wf
- **DIA-NN docs:** https://github.com/vdemichev/DiaNN
- **Nextflow docs:** https://nextflow.io/docs/latest/

---

*Last updated: 2026-03-28*
*This file is specifically for AI assistants working on the project*
