# DIA-NN Nextflow Workflow - AI Assistant Guide

This document provides context for AI assistants (like Claude) working on this project.

## Project Overview

A Nextflow DSL2 workflow for DIA-NN (Data-Independent Acquisition by Neural Networks) mass spectrometry analysis. The workflow supports library generation, model tuning, and sample quantification with SLURM HPC integration.

**Key Technology Stack:**
- **Nextflow** (DSL2) - Workflow orchestration
- **DIA-NN 2.3.1** - MS analysis tool (runs in Singularity containers)
- **SLURM** - HPC job scheduler
- **Singularity/Apptainer** - Container runtime

## Project Structure

```
diann-wf/
├── workflows/              # Complete workflow definitions
│   ├── compare_libraries.nf    # Compare default vs tuned libraries
│   ├── full_pipeline.nf        # Complete analysis pipeline
│   ├── quantify_only.nf        # Quantify with existing library
│   ├── create_library.nf       # Generate spectral library
│   └── tune_only.nf            # Tune prediction models
│
├── modules/                # Reusable process modules
│   ├── library.nf             # GENERATE_LIBRARY process
│   ├── tune.nf                # TUNE_MODELS process
│   └── quantify.nf            # QUANTIFY process
│
├── configs/                # Configuration files (reorganized!)
│   ├── workflows/             # Multi-module workflows
│   │   ├── compare_libraries.yaml
│   │   └── full_pipeline.yaml
│   ├── quantify/              # Single module configs
│   │   ├── basic.yaml
│   │   ├── ultrafast.yaml
│   │   └── batch_correction.yaml
│   ├── library/
│   │   └── standard.yaml
│   └── tune/
│       └── standard.yaml
│
└── nextflow.config         # Main configuration (profiles, resources)
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

## Important Patterns

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

// Correct - library broadcasts to all samples
QUANTIFY(samples_ch, library.first(), ...)
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

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

## Testing Strategy

**Local testing (standard profile):**
```bash
nextflow run workflows/quantify_only.nf \
  -params-file configs/quantify/basic.yaml \
  -profile standard
```

**SLURM testing:**
```bash
nextflow -bg run workflows/quantify_only.nf \
  -params-file configs/quantify/basic.yaml \
  -profile slurm
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
- `diann_version`: DIA-NN version (default: 2.3.1)
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
- `pg_level`: Protein group level (1=proteins, 0=genes)
- `mass_acc_cal`: Mass accuracy calibration threshold
- `smart_profiling`: Use smart profiling (default: true)
- `matrices`: Generate result matrices (default: true)
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
// QUANTIFY
input:
tuple val(sample_id), path(ms_dir), val(file_type), val(subdir)

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

// Compare libraries workflow
def subdir_default = 'quant/default'
def subdir_tuned = 'quant/tuned'
```

## Contact & Resources

- **Primary user:** karlssoc
- **Repository:** https://github.com/karlssoc/diann-wf
- **DIA-NN docs:** https://github.com/vdemichev/DiaNN
- **Nextflow docs:** https://nextflow.io/docs/latest/

---

*Last updated: 2025-12-17*
*This file is specifically for AI assistants working on the project*
