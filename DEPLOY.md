# Deployment Guide: Using diann-wf on Your Server

This guide shows how to use the workflow from GitHub on your remote server (e.g., kraken).

## Quick Start on Remote Server

### 1. Prerequisites on Server

Ensure you have:
```bash
# Check Nextflow (should be >= 21.04.0)
nextflow -version

# Check Singularity/Apptainer
singularity --version

# Check SLURM
squeue --version
```

If Nextflow is not installed:
```bash
# Install Nextflow
curl -s https://get.nextflow.io | bash
mv nextflow ~/bin/  # or anywhere in your $PATH
```

### 2. Project Setup on Server

Create a project directory for each analysis:

```bash
# Example: Create project for experiment
cd /srv/data1/karlssoc/projects/
mkdir my_diann_experiment
cd my_diann_experiment

# Create directories
mkdir -p input output configs
```

### 3. Create Your Configuration

Create a config file with **absolute paths** to your server data:

```bash
cat > configs/my_quantification.yaml << 'EOF'
# Simple quantification configuration
library: '/srv/data1/karlssoc/libraries/idmapping_2025_11_20.predicted.speclib'
fasta: '/srv/data1/karlssoc/fasta/idmapping_2025_11_20.fasta'

samples:
  - id: 'sample1'
    dir: '/srv/data1/karlssoc/projects/my_diann_experiment/input/sample1'
    file_type: 'd'

  - id: 'sample2'
    dir: '/srv/data1/karlssoc/projects/my_diann_experiment/input/sample2'
    file_type: 'd'

# Resources
threads: 60
outdir: '/srv/data1/karlssoc/projects/my_diann_experiment/results'

# SLURM
slurm_account: 'my_username'

# Quantification parameters
pg_level: 1
mass_acc_cal: 25
smart_profiling: true
individual_mass_acc: true
matrices: true
EOF
```

### 4. Run from GitHub

No need to clone the repository! Nextflow downloads it automatically:

```bash
# Run quantification workflow
nextflow run karlssoc/diann-wf \
  -params-file configs/my_quantification.yaml \
  -profile slurm \
  -r main

# First run will download the workflow automatically
```

### 5. Monitor Execution

```bash
# Check SLURM jobs
squeue -u $USER

# View Nextflow log
tail -f .nextflow.log

# Check results
ls -lh results/
```

## Example Project Structures

### Example 1: Simple Quantification Project

```
/srv/data1/karlssoc/projects/experiment_2024_12_10/
├── configs/
│   └── quantify_samples.yaml       # Your config
├── input/                           # Symlinks to raw data
│   ├── sample1 -> /data/raw/sample1
│   └── sample2 -> /data/raw/sample2
└── results/                         # Output directory
    ├── sample1/
    │   ├── report.parquet
    │   └── out-lib.parquet
    └── sample2/
        ├── report.parquet
        └── out-lib.parquet
```

### Example 2: Full Pipeline Project

```
/srv/data1/karlssoc/projects/comprehensive_analysis/
├── configs/
│   └── full_pipeline.yaml
├── input/
│   ├── sample1/
│   ├── sample2/
│   └── sample3/
└── results/
    ├── library/                    # Generated libraries
    │   ├── library_r1.predicted.speclib
    │   ├── library_r2.predicted.speclib
    │   └── library_r3.predicted.speclib
    ├── tuning/                     # Tuned models
    │   ├── out-lib.dict.txt
    │   ├── out-lib.tuned_rt.pt
    │   ├── out-lib.tuned_im.pt
    │   └── out-lib.tuned_fr.pt
    ├── sample1/
    ├── sample2/
    └── sample3/
```

## Common Usage Patterns

### Pattern 1: Quantify with Existing Library

```yaml
# configs/quick_quant.yaml
library: '/srv/data1/karlssoc/libraries/human_2024.predicted.speclib'
fasta: '/srv/data1/karlssoc/fasta/uniprot_human.fasta'
samples:
  - {id: 'exp01', dir: '/srv/data1/karlssoc/data/exp01', file_type: 'd'}
threads: 60
outdir: 'results/quantification'
slurm_account: 'my_username'
```

```bash
nextflow run karlssoc/diann-wf \
  -params-file configs/quick_quant.yaml \
  -profile slurm
```

### Pattern 2: Create Library

```yaml
# configs/new_library.yaml
fasta: '/srv/data1/karlssoc/fasta/mouse_proteome.fasta'
library_name: 'mouse_lib_2024'
threads: 60
outdir: 'results/library_creation'
slurm_account: 'my_username'
```

```bash
nextflow run karlssoc/diann-wf/workflows/create_library.nf \
  -params-file configs/new_library.yaml \
  -profile slurm
```

### Pattern 3: Full Multi-Round Pipeline

```yaml
# configs/comprehensive.yaml
fasta: '/srv/data1/karlssoc/fasta/yeast.fasta'
samples:
  - {id: 'rep1', dir: '/srv/data1/karlssoc/data/yeast/rep1', file_type: 'd'}
  - {id: 'rep2', dir: '/srv/data1/karlssoc/data/yeast/rep2', file_type: 'd'}
  - {id: 'rep3', dir: '/srv/data1/karlssoc/data/yeast/rep3', file_type: 'd'}
tune_sample: 'rep1'
run_r1: true
run_tune: true
run_r2: true
run_r3: true
threads: 60
outdir: 'results/full_pipeline'
slurm_account: 'my_username'
```

```bash
nextflow run karlssoc/diann-wf/workflows/full_pipeline.nf \
  -params-file configs/comprehensive.yaml \
  -profile slurm
```

## Updating the Workflow

When a new version is released:

```bash
# Pull latest version
nextflow pull karlssoc/diann-wf

# Or use specific version
nextflow run karlssoc/diann-wf -r v1.0.0 ...
```

## Version Pinning for Reproducibility

For publications, pin to a specific version:

```bash
# Use specific release tag
nextflow run karlssoc/diann-wf \
  -r v1.0.0 \
  -params-file configs/my_experiment.yaml \
  -profile slurm

# Document in your methods:
# "Analysis was performed using diann-wf v1.0.0
#  (https://github.com/karlssoc/diann-wf) with
#  DIA-NN 2.3.1"
```

## Troubleshooting

### Issue: Workflow not found

```bash
# Force update
nextflow pull karlssoc/diann-wf -f

# Check what's downloaded
nextflow info karlssoc/diann-wf
```

### Issue: Permission denied on results directory

```bash
# Ensure output directory is writable
chmod 755 results/
```

### Issue: Container pull fails

```bash
# Pre-pull containers manually
singularity pull diann_2.3.1.sif docker://quay.io/karlssoc/diann:2.3.1

# Or check your container cache
ls ~/.singularity/cache/
```

### Issue: SLURM jobs fail

```bash
# Check SLURM account is correct
sacctmgr show associations user=$USER format=account,qos

# View job details
scontrol show job <jobid>
```

## Resume Failed Runs

If a run fails or is interrupted:

```bash
# Resume from last successful checkpoint
nextflow run karlssoc/diann-wf \
  -params-file configs/my_config.yaml \
  -profile slurm \
  -resume
```

## Best Practices

1. **Use absolute paths** in configs
2. **One config per experiment** for reproducibility
3. **Test locally** with `-profile test` before SLURM
4. **Pin versions** for publications
5. **Keep configs in version control** (separate from workflow repo)
6. **Document DIANN version** used in your methods

## Example: Replicating Your Current tt/lfqb Workflow

```bash
# On kraken server
cd /srv/data1/karlssoc/projects/tt/lfqb/

# Create config for your existing data
cat > configs/ttht_pipeline.yaml << 'EOF'
fasta: '/srv/data1/karlssoc/projects/tt/lfqb/idmapping_2025_11_20.fasta'
samples:
  - id: 'mann'
    dir: '/srv/data1/karlssoc/projects/tt/lfqb/input/mann'
    file_type: 'd'
  - id: 'p2'
    dir: '/srv/data1/karlssoc/projects/tt/lfqb/input/p2'
    file_type: 'd'
  - id: 'std'
    dir: '/srv/data1/karlssoc/projects/tt/lfqb/input/std'
    file_type: 'd'

tune_sample: 'p2'
run_r1: true
run_tune: true
run_r2: true
run_r3: true

r1_diann_version: '2.3.1'
r2_diann_version: '2.2.0'
r3_diann_version: '2.3.1'

threads: 60
outdir: '/srv/data1/karlssoc/projects/tt/lfqb/results/nextflow_run'
slurm_account: 'my_username'

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
EOF

# Run the full pipeline
nextflow run karlssoc/diann-wf/workflows/full_pipeline.nf \
  -params-file configs/ttht_pipeline.yaml \
  -profile slurm
```

This replaces your entire series of scripts:
- `run_diann3-r1a.sh` → Round 1 (automatic)
- `tune-2.3.1-ttht-p2.sh` → Tuning (automatic)
- `run_diann3-r2a.sh` → Round 2 (automatic)
- `run_diann3-r3a.sh` → Round 3 (automatic)

All with dependency tracking, resume capability, and execution reports!
