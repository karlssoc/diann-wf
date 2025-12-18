# DIANN Nextflow Workflows

Modular Nextflow workflows for DIA-NN mass spectrometry analysis with SLURM integration.

## Overview

This workflow system provides five flexible entry points for different use cases:

1. **[quantify_only.nf](workflows/quantify_only.nf)** - Simple quantification with existing library (90% of use cases)
2. **[create_library.nf](workflows/create_library.nf)** - Create spectral library from FASTA
3. **[repredict_library.nf](workflows/repredict_library.nf)** - Generate new spectral library using DIA-NN predictor based on peptides from existing library
4. **[full_pipeline.nf](workflows/full_pipeline.nf)** - Complete multi-round pipeline with model tuning
5. **[compare_libraries.nf](workflows/compare_libraries.nf)** - Compare default vs tuned library quantification

## Quick Start

### 1. Simple Quantification (Most Common)

When you have an existing library and just need to quantify samples:

```bash
# Pull the workflow from GitHub (first time only)
nextflow pull karlssoc/diann-wf

# Edit the config file with your paths
nano configs/quantify/basic.yaml

# Run locally for testing
nextflow run karlssoc/diann-wf -entry quantify_only \
  -params-file configs/quantify/basic.yaml

# Submit to SLURM (recommended - runs in background)
nextflow -bg run karlssoc/diann-wf -entry quantify_only \
  -params-file configs/quantify/basic.yaml -profile slurm
```

### 2. Create Library

Generate a spectral library from a FASTA file:

```bash
# Edit the config file
nano configs/library/standard.yaml

# Run with SLURM (in background)
nextflow -bg run karlssoc/diann-wf -entry create_library \
  -params-file configs/library/standard.yaml -profile slurm
```

### 3. Full Pipeline

Complete multi-round analysis with model tuning (rare, for comprehensive studies):

```bash
# Edit the config file
nano configs/workflows/full_pipeline.yaml

# Run with SLURM (specify workflow explicitly for full pipeline)
nextflow -bg run karlssoc/diann-wf/workflows/full_pipeline.nf \
  -params-file configs/workflows/full_pipeline.yaml -profile slurm
```

### 4. Compare Libraries

Compare quantification using default vs tuned libraries side-by-side:

```bash
# Edit the config file
nano configs/workflows/compare_libraries.yaml

# Run with SLURM (specify workflow explicitly)
nextflow -bg run karlssoc/diann-wf/workflows/compare_libraries.nf \
  -params-file configs/workflows/compare_libraries.yaml -profile slurm
```

**Use when:** You want to evaluate the impact of model tuning on quantification results.

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

- **`-profile slurm`** - Singularity with SLURM executor (generic HPC)
- **`-profile cosmos`** - Optimized for LUNARC COSMOS HPC (48 cores, local disk staging)
- **`-profile docker_slurm`** - Docker with SLURM executor
- **`-profile podman_slurm`** - Podman with SLURM executor

### COSMOS HPC Profile

The `cosmos` profile is optimized for the [LUNARC COSMOS cluster](https://www.lunarc.lu.se/systems/cosmos):

**Key optimizations:**
- ✅ **48 cores** per node (AMD Milan) - automatically configured
- ✅ **Local disk staging** - MS files copied to 2 TB node-local disk for 10-50x faster I/O
- ✅ **Optimal parallel mode** - 2×24 core jobs for better throughput
- ✅ **SLURM tuning** - Timeouts and poll intervals optimized for shared cluster

**Usage:**
```bash
# Simple quantification on COSMOS
nextflow -bg run karlssoc/diann-wf -entry quantify_only \
  -params-file configs/cosmos/quantify_example.yaml \
  -profile cosmos

# Full pipeline on COSMOS
nextflow -bg run karlssoc/diann-wf/workflows/full_pipeline.nf \
  -params-file configs/cosmos/full_pipeline_example.yaml \
  -profile cosmos
```

**Important:** Set your LUNARC project in the config:
```yaml
slurm_account: 'YOUR_LUNARC_PROJECT'  # Required for COSMOS
slurm_queue: 'lu'                     # Default partition
```

**Local disk benefits:**
- Bruker `.d` files (many small files): **Massive speedup**
- Large RAW files (repeated reads): **10-50x faster**
- Reduces network filesystem contention

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

### Workflow 3: Repredict Library

**Use when:** You have an existing spectral library (e.g., from a previous search or run) and want to generate a new predicted library using DIA-NN's predictor, optionally with tuned models, while keeping the same peptide identifications.

**What it does:**
- Takes an existing spectral library as input (e.g., `.predicted.speclib`, `.parquet`, `.tsv`)
- Generates new spectral library predictions for those peptides using current/tuned models
- Useful for transferring a library to a different instrument or updating predictions with better models

```bash
nextflow run karlssoc/diann-wf/workflows/repredict_library.nf \
  --fasta mydata.fasta \
  --input_library results/previous_run/sample1/out-lib.parquet \
  --library_name repredicted_lib \
  --outdir results/repredicted_library \
  -profile slurm
```

Or use a config file:

```yaml
# configs/library/repredict.yaml
fasta: '/path/to/protein.fasta'
input_library: '/path/to/existing/library.predicted.speclib'
library_name: 'repredicted_lib'
outdir: 'results/repredicted_library'
diann_version: '2.3.1'
threads: 48
slurm_account: 'my_username'

# Optional: Use tuned models
# tokens: 'results/tuning/out-lib.dict.txt'
# rt_model: 'results/tuning/out-lib.tuned_rt.pt'
# im_model: 'results/tuning/out-lib.tuned_im.pt'
# fr_model: 'results/tuning/out-lib.tuned_fr.pt'
```

```bash
nextflow -bg run karlssoc/diann-wf/workflows/repredict_library.nf \
  -params-file configs/library/repredict.yaml \
  -profile slurm
```

### Workflow 4: Full Pipeline

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

### Workflow 5: Compare Libraries

**Use when:** You want to evaluate the impact of model tuning by comparing quantification results side-by-side.

This workflow performs:
1. **Generate default library:** Create library with default DIANN models
2. **Tune models:** Use external library to tune RT/IM/FR prediction models
3. **Generate tuned library:** Create library with tuned models
4. **Quantify with both:** Run quantification using both libraries for direct comparison

```yaml
# configs/compare_libraries.yaml
tune_library: 'results/previous_run/sample1/out-lib.parquet'
fasta: 'mydata.fasta'
samples:
  - id: 'exp01'
    dir: 'input/exp01'
    file_type: 'raw'
library_name: 'comparison'
diann_version: '2.3.1'
threads: 60
slurm_account: 'my_username'
```

```bash
nextflow -bg run karlssoc/diann-wf/workflows/compare_libraries.nf \
  -params-file configs/compare_libraries.yaml \
  -profile slurm
```

**Output organization:**
```
results/library_comparison/
├── default_library/         # Library with default models
├── tuned_library/           # Library with tuned models
├── tuning/                  # Tuned model files
├── default/                 # Quantification using default library
│   └── exp01/
│       ├── report.parquet
│       └── out-lib.parquet
└── tuned/                   # Quantification using tuned library
    └── exp01/
        ├── report.parquet
        └── out-lib.parquet
```

**Use cases:**
- Benchmark the improvement from model tuning
- Validate tuning effectiveness for your dataset
- A/B testing of library generation strategies

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

## Working with Remote Storage (SMB/CIFS, Network Mounts)

The workflow **already supports** reading input data from SMB shares and network mounts. Simply specify the mounted path in your config.

### Example: Using SMB Mount on kraken

```yaml
# configs/quantify/smb_example.yaml
library: '/mnt/imp_arch/libraries/mylib.predicted.speclib'
fasta: '/mnt/imp_arch/fasta/proteome.fasta'

samples:
  - id: 'sample1'
    dir: '/mnt/imp_arch/raw_data/experiment1/sample1'  # SMB path
    file_type: 'd'

# Output to local storage (faster than SMB)
outdir: '/scratch/results/quantification'
```

```bash
nextflow -bg run karlssoc/diann-wf \
  -params-file configs/quantify/smb_example.yaml \
  -profile slurm
```

### How Nextflow Handles Remote Storage

**Automatic staging:**
1. Nextflow reads your input paths (can be SMB, NFS, any mounted filesystem)
2. Stages files to the work directory before processing
3. **With `-profile cosmos`:** Stages to `$SNIC_TMP` (2 TB local disk) for maximum I/O performance
4. DIA-NN processes from fast local disk
5. Results written back to `outdir` (can be SMB or local)

### Performance Considerations

#### ✅ Best Performance (COSMOS with local disk staging)

```bash
nextflow -bg run karlssoc/diann-wf \
  -params-file configs/quantify/smb_example.yaml \
  -profile cosmos  # Automatic local disk staging
```

**What happens:**
- Input MS files copied from SMB → `$SNIC_TMP` (local disk)
- DIA-NN reads from local disk (10-50x faster than SMB)
- Only initial copy is over network

#### ⚠️ Slower but Still Works (Direct SMB access)

```bash
nextflow -bg run karlssoc/diann-wf \
  -params-file configs/quantify/smb_example.yaml \
  -profile slurm  # No local disk staging on kraken
```

**What happens:**
- Nextflow stages files to work directory (still on network FS)
- DIA-NN reads directly from SMB mount
- Slower due to network latency on random access

### Recommendations

| Scenario | Recommendation |
|----------|---------------|
| **COSMOS HPC** | Use `-profile cosmos` (automatic local disk staging) |
| **kraken server** | Consider pre-copying large datasets to local storage |
| **Small datasets** | Direct SMB access is fine |
| **Bruker .d files** | **Always** use local disk staging (many small files) |

### Pre-staging Data (Optional)

For very large datasets on kraken without local disk staging:

```bash
# Option 1: rsync to local storage before running
rsync -avP /mnt/imp_arch/raw_data/experiment1/ /scratch/staged_data/

# Then use local path in config
dir: '/scratch/staged_data/sample1'

# Option 2: Let Nextflow handle it (automatic with scratch)
```

### Supported Storage Types

The workflow works with any filesystem mounted on your system:

- ✅ **SMB/CIFS** (Windows shares, e.g., `/mnt/imp_arch`)
- ✅ **NFS** (Unix/Linux network shares)
- ✅ **Local filesystems** (ext4, xfs, etc.)
- ✅ **Lustre/GPFS** (HPC parallel filesystems)
- ✅ **Object storage with FUSE** (if mounted)

**Note:** Path must be accessible from all compute nodes. On SLURM clusters, ensure SMB mount is available on all nodes, or use COSMOS with local disk staging.

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

## Output Structure

### Quantify Only Workflow

```
results/
├── sample1/
│   ├── report.parquet          # Main quantification results
│   ├── out-lib.parquet          # Output library
│   ├── *.tsv                    # Matrix files (if matrices: true)
│   └── diann.log                # DIANN log
├── sample2/
│   └── ...
└── pipeline_info/               # Nextflow execution reports
    ├── execution_report.html
    ├── execution_timeline.html
    └── execution_trace.txt
```

### Full Pipeline Workflow

```
results/
├── stage1/                      # Round 1: Default models
│   ├── library/
│   │   └── library.predicted.speclib
│   ├── sample1/
│   ├── sample2/
│   └── sample3/
├── tuning/                      # Tuned models
│   ├── out-lib.dict.txt
│   ├── out-lib.tuned_rt.pt
│   ├── out-lib.tuned_im.pt
│   └── out-lib.tuned_fr.pt
├── stage2/                      # Round 2: RT+IM tuned
│   ├── library/
│   ├── sample1/
│   ├── sample2/
│   └── sample3/
└── stage3/                      # Round 3: RT+IM+FR tuned
    ├── library/
    ├── sample1/
    ├── sample2/
    └── sample3/
```

## Deployment

### Push to GitHub

```bash
# 1. Create repository on GitHub: https://github.com/new
#    Name: diann-wf
#    Visibility: Public or Private
#    Don't initialize with README

# 2. Push to GitHub
git remote add origin git@github.com:YOUR_USERNAME/diann-wf.git
git push -u origin main

# 3. (Optional) Create release tag
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin v1.0.0
```

### Use from GitHub on HPC

```bash
# Pull workflow (first time or to update)
nextflow pull YOUR_USERNAME/diann-wf

# Run from GitHub
nextflow -bg run YOUR_USERNAME/diann-wf \
  -params-file configs/my_config.yaml \
  -profile cosmos  # or slurm

# Use specific version (for reproducibility)
nextflow run YOUR_USERNAME/diann-wf \
  -r v1.0.0 \
  -params-file configs/my_config.yaml \
  -profile cosmos
```

## Tips

1. **Always use `-bg` for SLURM:** Persist through terminal disconnections
2. **Start simple:** Use `quantify_only.nf` for most tasks
3. **Test locally first:** Use `-profile test` before SLURM submission
4. **Use `-resume`:** Save time by resuming failed runs
5. **Check reports:** Review execution reports to optimize resource usage
6. **Version control configs:** Keep your YAML configs in git for reproducibility
7. **Pin versions for publications:** Use `-r v1.0.0` for reproducibility

## TODO

- [ ] Test `-profile cosmos` on COSMOS cluster with real data
- [ ] Check if all quantify output files are included
- [ ] Integration with storage (SMB, Swestore, OpenBIS, seqera)
- [ ] `.speclib` to `.parquet`?
```
    lib="library.predicted.speclib"
    outlib="${lib%.speclib}.parquet"

    diann-linux \
        --lib "$lib" \
        --gen-spec-lib \
        --out-lib "$outlib" 
```        
- [ ] MS profiles (ttht-evosep-30SPD, hfx-vneo-24SPD) using sets of tuned parameters

## Support

For issues or questions:
- Check Nextflow docs: https://www.nextflow.io/docs/latest/
- Check DIANN docs: https://github.com/vdemichev/DiaNN
- Review execution logs in `results/pipeline_info/`


## License

This workflow system is provided as-is for research use.
