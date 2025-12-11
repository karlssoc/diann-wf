# Quick Start Guide

Get started with DIANN workflows in 5 minutes.

## Prerequisites

Ensure you have:
- Nextflow installed: `nextflow -version`
- Singularity/Apptainer available
- Access to SLURM cluster (optional, can run locally)

## Step 1: Setup Your Config

Choose the workflow you need and copy the example config:

```bash
# For simple quantification (most common)
cp configs/simple_quant.yaml configs/my_experiment.yaml

# For library creation
cp configs/library_creation.yaml configs/my_library.yaml

# For full pipeline
cp configs/full_pipeline.yaml configs/my_pipeline.yaml
```

## Step 2: Edit Your Config

Edit the config file with your actual paths:

```bash
nano configs/my_experiment.yaml
```

**Minimum changes needed:**
1. Update `library:` path to your spectral library
2. Update `fasta:` path to your FASTA file
3. Update `samples:` with your sample directories
4. Update `slurm_account:` with your SLURM account name

Example:
```yaml
library: '/srv/data1/karlssoc/libraries/mylib.predicted.speclib'
fasta: '/srv/data1/karlssoc/fasta/mydata.fasta'
samples:
  - id: 'experiment_01'
    dir: '/srv/data1/karlssoc/data/exp01'
    file_type: 'd'   # or 'raw' or 'mzML'
slurm_account: 'my_username'
```

## Step 3: Test Locally (Optional but Recommended)

Test your workflow locally before submitting to SLURM:

```bash
# Pull the workflow from GitHub (first time only)
nextflow pull karlssoc/diann-wf

# Test run with minimal resources
nextflow run karlssoc/diann-wf \
  -params-file configs/my_experiment.yaml \
  -profile test
```

If errors occur, check:
- File paths are correct and accessible
- Directories exist
- Permissions are correct

## Step 4: Run on SLURM

Once testing works, submit to SLURM:

```bash
# Run from GitHub (recommended - always gets latest version)
nextflow run karlssoc/diann-wf \
  -params-file configs/my_experiment.yaml \
  -profile slurm

# Or specify a workflow explicitly:
nextflow run karlssoc/diann-wf/workflows/quantify_only.nf \
  -params-file configs/my_experiment.yaml \
  -profile slurm
```

**Note:** The workflow is pulled from GitHub automatically. No need to clone the repository!

The workflow will:
1. Create SLURM jobs automatically
2. Submit them to the queue
3. Track dependencies
4. Report progress

## Step 5: Monitor Progress

```bash
# Check running jobs
squeue -u $USER

# View Nextflow log
tail -f .nextflow.log

# List all runs
nextflow log
```

## Step 6: Check Results

Results are saved to the `outdir` specified in your config:

```bash
# Default location
ls -lh results/

# Each sample gets its own directory
ls -lh results/experiment_01/
# - report.parquet       # Main results
# - out-lib.parquet      # Output library
# - *.tsv                # Matrix files
# - diann.log            # DIANN log

# Pipeline execution reports
ls -lh results/pipeline_info/
# - execution_report.html    # Resource usage
# - execution_timeline.html  # Timeline
# - pipeline_dag.svg         # Workflow diagram
```

## Common Use Cases

### Use Case 1: Quantify Multiple Samples with Existing Library

```yaml
# configs/batch_quant.yaml
library: 'mylib.predicted.speclib'
fasta: 'mydata.fasta'
samples:
  - {id: 'sample1', dir: 'input/sample1', file_type: 'd'}
  - {id: 'sample2', dir: 'input/sample2', file_type: 'd'}
  - {id: 'sample3', dir: 'input/sample3', file_type: 'd'}
  - {id: 'sample4', dir: 'input/sample4', file_type: 'd'}
threads: 60
slurm_account: 'my_username'
```

```bash
# Run from GitHub (recommended - always gets latest version)
nextflow run karlssoc/diann-wf -params-file configs/batch_quant.yaml -profile slurm
```

### Use Case 2: Create New Library from FASTA

```yaml
# configs/new_library.yaml
fasta: 'new_organism.fasta'
library_name: 'new_organism_lib'
threads: 60
slurm_account: 'my_username'
```

```bash
# Run from GitHub (specify workflow explicitly for library creation)
nextflow run karlssoc/diann-wf/workflows/create_library.nf -params-file configs/new_library.yaml -profile slurm
```

### Use Case 3: Full Pipeline with Model Tuning

```yaml
# configs/tuned_pipeline.yaml
fasta: 'mydata.fasta'
samples:
  - {id: 'sample1', dir: 'input/sample1', file_type: 'd'}
  - {id: 'sample2', dir: 'input/sample2', file_type: 'd'}
tune_sample: 'sample1'  # Use sample1 for tuning
run_r1: true
run_tune: true
run_r2: true
threads: 60
slurm_account: 'my_username'
```

```bash
# Run from GitHub (specify workflow explicitly for full pipeline)
nextflow run karlssoc/diann-wf/workflows/full_pipeline.nf -params-file configs/tuned_pipeline.yaml -profile slurm
```

## Troubleshooting

### Problem: "File not found" errors

**Solution:** Check file paths are absolute, not relative:
```yaml
# Wrong
fasta: 'data/mydata.fasta'

# Correct
fasta: '/full/path/to/data/mydata.fasta'
```

### Problem: SLURM jobs fail immediately

**Solution:** Check SLURM account is correct:
```bash
# Check your accounts
sacctmgr show associations user=$USER format=account,qos
```

### Problem: Out of memory errors

**Solution:** Increase memory allocation in `nextflow.config`:
```groovy
withLabel: 'diann_quantify' {
    memory = '50 GB'  // Increase from default
}
```

### Problem: Want to resume after failure

**Solution:** Use `-resume` flag:
```bash
nextflow run karlssoc/diann-wf \
  -params-file configs/my_experiment.yaml \
  -profile slurm \
  -resume
```

## Tips for Success

1. **Always test locally first** with `-profile test`
2. **Use absolute paths** in your configs
3. **Start with one sample** to test before running many
4. **Check logs** in `results/pipeline_info/`
5. **Use `-resume`** to restart failed runs without recomputing
6. **Keep configs in version control** (git) for reproducibility

## Next Steps

- Read the full [README.md](README.md) for advanced features
- Customize parameters for your specific needs
- Check execution reports to optimize resource usage
- Set up different configs for different experiments

## Need Help?

1. Check the [README.md](README.md) for detailed documentation
2. Review `.nextflow.log` for detailed error messages
3. Check SLURM logs: `results/<sample>/slurm-*.log`
4. Verify container access: `singularity pull docker://quay.io/karlssoc/diann:2.3.1`
