# DIANN Nextflow Workflows

Modular Nextflow workflows for DIA-NN mass spectrometry analysis with SLURM integration.

## Overview

This workflow system provides three flexible entry points for different use cases:

1. **[quantify_only.nf](workflows/quantify_only.nf)** - Simple quantification with existing library (90% of use cases)
2. **[create_library.nf](workflows/create_library.nf)** - Create spectral library from FASTA
3. **[full_pipeline.nf](workflows/full_pipeline.nf)** - Complete multi-round pipeline with model tuning

## Quick Start

### 1. Simple Quantification (Most Common)

When you have an existing library and just need to quantify samples:

```bash
# Pull the workflow from GitHub (first time only)
nextflow pull karlssoc/diann-wf

# Edit the config file with your paths
nano configs/simple_quant.yaml

# Run locally for testing
nextflow run karlssoc/diann-wf -entry quantify_only \
  -params-file configs/simple_quant.yaml

# Submit to SLURM (recommended - runs in background)
nextflow -bg run karlssoc/diann-wf -entry quantify_only \
  -params-file configs/simple_quant.yaml -profile slurm
```

### 2. Create Library

Generate a spectral library from a FASTA file:

```bash
# Edit the config file
nano configs/library_creation.yaml

# Run with SLURM (in background)
nextflow -bg run karlssoc/diann-wf -entry create_library \
  -params-file configs/library_creation.yaml -profile slurm
```

### 3. Full Pipeline

Complete multi-round analysis with model tuning (rare, for comprehensive studies):

```bash
# Edit the config file
nano configs/full_pipeline.yaml

# Run with SLURM (specify workflow explicitly for full pipeline)
nextflow -bg run karlssoc/diann-wf/workflows/full_pipeline.nf -params-file configs/full_pipeline.yaml -profile slurm
```

## Requirements

- Nextflow >= 21.04.0
- Container runtime (choose one):
  - Singularity/Apptainer (recommended for HPC)
  - Docker or OrbStack (for local development)
  - Podman (alternative to Docker)
- Access to DIANN containers: `quay.io/karlssoc/diann`

Available DIANN versions:
- `2.3.1` (latest, includes FR tuning)
- `2.3.0-beta`
- `2.2.0` (stable)
- `1.8.1`

## Execution Profiles

The workflow supports multiple container runtimes and execution environments. Choose the profile that matches your setup:

### Local Execution

- **`-profile standard`** - Singularity with local executor (default)
- **`-profile docker`** - Docker with local executor
- **`-profile podman`** - Podman with local executor

### SLURM Cluster Execution

- **`-profile slurm`** - Singularity with SLURM executor (recommended for HPC)
- **`-profile docker_slurm`** - Docker with SLURM executor
- **`-profile podman_slurm`** - Podman with SLURM executor

### Examples

```bash
# Local with Docker (macOS/OrbStack)
nextflow run karlssoc/diann-wf -entry quantify_only \
  -params-file configs/simple_quant.yaml -profile docker

# Local with Podman
nextflow run karlssoc/diann-wf -entry create_library \
  -params-file configs/library_creation.yaml -profile podman

# SLURM with Singularity (HPC)
nextflow run karlssoc/diann-wf -entry quantify_only \
  -params-file configs/simple_quant.yaml -profile slurm

# SLURM with Docker
nextflow run karlssoc/diann-wf -entry quantify_only \
  -params-file configs/simple_quant.yaml -profile docker_slurm
```

### ⚠️ Important: ARM/Apple Silicon Warning

**The DIANN container is x86-64 only.** When running on ARM Macs (Apple Silicon) with Docker or Podman, the container runs via Rosetta 2 emulation.

**Rosetta 2 emulation can produce different scientific results:**
- Lower identification rates
- Altered quantification values
- Differences in floating-point precision
- Changes in numeric calculations

**Recommendations:**
- **Testing/Development:** Docker/Podman on ARM Macs is acceptable for workflow development and testing
- **Production/Publication:** Use native x86-64 hardware or SLURM cluster with Singularity for reproducible results
- The workflow automatically displays a warning when running on ARM with Docker/Podman

## Project Structure

```
diann-wf/
├── nextflow.config          # Base configuration
├── workflows/
│   ├── quantify_only.nf     # Simple quantification
│   ├── create_library.nf    # Library creation
│   └── full_pipeline.nf     # Complete multi-round pipeline
├── modules/
│   ├── quantify.nf          # Quantification process
│   ├── library.nf           # Library generation process
│   └── tune.nf              # Model tuning process
└── configs/
    ├── simple_quant.yaml    # Example: quantification
    ├── library_creation.yaml # Example: library creation
    └── full_pipeline.yaml   # Example: full pipeline
```

## Configuration

### Sample Definition

Samples are defined in YAML format with automatic file-type detection:

```yaml
samples:
  - id: 'sample1'
    dir: 'input/sample1'
    file_type: 'd'          # Bruker .d files

  - id: 'sample2'
    dir: 'input/sample2'
    file_type: 'raw'        # Thermo .raw files

  - id: 'sample3'
    dir: 'input/sample3'
    file_type: 'mzML'       # mzML files
```

**Important:** `.d` files automatically get `--mass-acc 15 --mass-acc-ms1 15` parameters.

### SLURM Configuration

Configure SLURM settings in your config file:

```yaml
slurm_account: 'my_username'
slurm_queue: 'normal'        # Optional
threads: 60
```

Resource allocation is automatic based on process type:
- **Tuning:** 10 CPUs, 10 GB RAM, 2h
- **Library:** 60 CPUs, 30 GB RAM, 4h
- **Quantification:** 60 CPUs, 30 GB RAM, 8h

Override in `nextflow.config` if needed.

## Detailed Usage

### Workflow 1: Quantify Only

**Use when:** You have an existing spectral library and need to quantify samples.

```bash
nextflow run karlssoc/diann-wf \
  --library /path/to/library.predicted.speclib \
  --fasta mydata.fasta \
  --samples '[{"id":"exp01","dir":"input/exp01","file_type":"d"}]' \
  --outdir results/exp01 \
  -profile slurm
```

Or use a config file:

```yaml
# configs/my_quant.yaml
library: '/srv/data1/karlssoc/libraries/mylib.predicted.speclib'
fasta: 'mydata.fasta'
samples:
  - id: 'exp01'
    dir: 'input/exp01'
    file_type: 'd'
outdir: 'results/exp01'
diann_version: '2.3.1'
threads: 60
slurm_account: 'my_username'
```

```bash
nextflow -bg run karlssoc/diann-wf -params-file configs/my_quant.yaml -profile slurm
```

### Workflow 2: Create Library

**Use when:** You need to generate a new spectral library from a FASTA file.

#### Option A: Default Models

```bash
nextflow run karlssoc/diann-wf/workflows/create_library.nf \
  --fasta mydata.fasta \
  --library_name mylib \
  --outdir results/library \
  -profile slurm
```

#### Option B: With Tuned Models

If you have pre-tuned models from a previous run:

```bash
nextflow run karlssoc/diann-wf/workflows/create_library.nf \
  --fasta mydata.fasta \
  --library_name mylib_tuned \
  --tokens results/tuning/out-lib.dict.txt \
  --rt_model results/tuning/out-lib.tuned_rt.pt \
  --im_model results/tuning/out-lib.tuned_im.pt \
  --fr_model results/tuning/out-lib.tuned_fr.pt \
  -profile slurm
```

### Workflow 3: Full Pipeline

**Use when:** You need comprehensive analysis with model optimization across multiple rounds.

This workflow performs:
1. **Round 1:** Generate library with default models → Quantify all samples
2. **Tuning:** Fine-tune RT/IM/FR models using specified sample
3. **Round 2:** Generate library with RT+IM models → Quantify all samples
4. **Round 3:** Generate library with RT+IM+FR models → Quantify all samples

```bash
nextflow -bg run karlssoc/diann-wf/workflows/full_pipeline.nf -params-file configs/full_pipeline.yaml -profile slurm
```

#### Control Which Rounds to Run

```bash
# Only R1 and tuning (skip R2/R3)
nextflow -bg run karlssoc/diann-wf/workflows/full_pipeline.nf \
  -params-file configs/full_pipeline.yaml \
  --run_r2 false \
  --run_r3 false \
  -profile slurm

# Skip R1, only R2 and R3 (if you already have tuned models)
nextflow -bg run karlssoc/diann-wf/workflows/full_pipeline.nf \
  -params-file configs/full_pipeline.yaml \
  --run_r1 false \
  -profile slurm
```

## Advanced Features

### Background Execution (`-bg` Flag)

**Important for SLURM users:** Use the `-bg` flag to run Nextflow in the background. This ensures your workflow continues even if your terminal session disconnects (e.g., SSH timeout, network issues, or closing your laptop).

```bash
# Run in background - workflow persists even if you disconnect
nextflow -bg run karlssoc/diann-wf \
  -params-file configs/simple_quant.yaml \
  -profile slurm
```

**What `-bg` does:**
- Runs Nextflow in the background (similar to `nohup`)
- Detaches from your terminal
- Saves logs to `.nextflow.log` automatically
- Perfect for long-running SLURM workflows

**Monitor your background workflow:**
```bash
# Find the Nextflow process
ps aux | grep nextflow

# Monitor the log file
tail -f .nextflow.log

# Check SLURM jobs
squeue -u $USER
```

**Alternative:** You can also use `tmux` or `screen` to create persistent terminal sessions, but `-bg` is simpler and built into Nextflow.

### Resume Failed Runs

Nextflow can resume interrupted workflows:

```bash
nextflow -bg run karlssoc/diann-wf -params-file configs/simple_quant.yaml -resume
```

### Use Different DIANN Versions

```bash
# Command line override
nextflow -bg run karlssoc/diann-wf \
  -params-file configs/simple_quant.yaml \
  --diann_version 2.2.0 \
  -profile slurm

# Or in config file
diann_version: '2.2.0'
```

### Custom Library Parameters

Modify library generation parameters in your config:

```yaml
library:
  min_fr_mz: 200
  max_fr_mz: 1800
  min_pep_len: 7
  max_pep_len: 30
  min_pr_mz: 350
  max_pr_mz: 1650
  min_pr_charge: 2
  max_pr_charge: 3
  cut: 'K*,R*'
  missed_cleavages: 1
  met_excision: true
  unimod4: true
```

### File Type Detection

The workflow automatically applies appropriate parameters based on file type:

| File Type | Parameters Applied |
|-----------|-------------------|
| `.d` (Bruker) | `--mass-acc 15 --mass-acc-ms1 15` |
| `.raw` (Thermo) | Default DIANN parameters |
| `.mzML` | Default DIANN parameters |

## Execution Reports

Nextflow automatically generates execution reports in `results/pipeline_info/`:

- `execution_timeline.html` - Timeline of process execution
- `execution_report.html` - Resource usage statistics
- `execution_trace.txt` - Detailed execution trace
- `pipeline_dag.svg` - Visual workflow diagram

## Troubleshooting

### Check Workflow Status

```bash
# List running workflows
nextflow log

# View specific run details
nextflow log <run_name> -f status,name,exit,duration
```

### Test Locally Before SLURM

```bash
# Run with minimal resources for testing
nextflow run karlssoc/diann-wf \
  -params-file configs/simple_quant.yaml \
  -profile test
```

### Container Issues

If containers fail to download:

```bash
# Pre-pull containers
singularity pull diann_2.3.1.sif docker://quay.io/karlssoc/diann:2.3.1

# Update nextflow.config to use local SIF
process.container = '/path/to/diann_2.3.1.sif'
```

## Examples from Your Remote Server

Based on your existing scripts on `kraken:/srv/data1/karlssoc/projects/tt/lfqb/`:

### Example 1: Simple Quantification (like run_diann3-r1b.sh)

```yaml
# configs/ttht_quant.yaml
library: 'idmapping_2025_11_20.predicted.speclib'
fasta: 'idmapping_2025_11_20.fasta'
samples:
  - id: 'hfx-30SPD'
    dir: 'input/hfx-30SPD'
    file_type: 'raw'
  - id: 'hfx-50SPD'
    dir: 'input/hfx-50SPD'
    file_type: 'raw'
diann_version: '2.2.0'
threads: 60
slurm_account: 'my_username'
```

```bash
nextflow -bg run karlssoc/diann-wf -params-file configs/ttht_quant.yaml -profile slurm
```

### Example 2: Full Pipeline (like your run_diann3-r2a.sh and r3a.sh)

```yaml
# configs/ttht_full.yaml
fasta: 'idmapping_2025_11_20.fasta'
samples:
  - {id: 'mann', dir: 'input/mann', file_type: 'd'}
  - {id: 'p2', dir: 'input/p2', file_type: 'd'}
  - {id: 'std', dir: 'input/std', file_type: 'd'}
tune_sample: 'p2'
run_r1: true
run_tune: true
run_r2: true
run_r3: true
r2_diann_version: '2.2.0'
r3_diann_version: '2.3.1'
threads: 60
slurm_account: 'my_username'
```

```bash
nextflow -bg run karlssoc/diann-wf/workflows/full_pipeline.nf -params-file configs/ttht_full.yaml -profile slurm
```

## Tips

1. **Always use `-bg` for SLURM:** Persist through terminal disconnections
2. **Start simple:** Use `quantify_only.nf` for most tasks
3. **Test locally first:** Use `-profile test` before SLURM submission
4. **Use `-resume`:** Save time by resuming failed runs
5. **Check reports:** Review execution reports to optimize resource usage
6. **Version control configs:** Keep your YAML configs in git for reproducibility

## Support

For issues or questions:
- Check Nextflow docs: https://www.nextflow.io/docs/latest/
- Check DIANN docs: https://github.com/vdemichev/DiaNN
- Review execution logs in `results/pipeline_info/`

## License

This workflow system is provided as-is for research use.
