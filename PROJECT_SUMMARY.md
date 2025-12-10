# DIANN Nextflow Workflow - Project Summary

## What Has Been Created

A complete, modular Nextflow workflow system for DIANN mass spectrometry analysis with three flexible entry points designed for different use cases.

## Project Structure

```
diann-wf/
├── README.md                      # Complete documentation
├── QUICKSTART.md                  # 5-minute quick start guide
├── PROJECT_SUMMARY.md             # This file
├── nextflow.config                # Base configuration (SLURM, containers, resources)
├── .gitignore                     # Git ignore rules
│
├── workflows/                     # Entry point workflows
│   ├── quantify_only.nf          # Simple quantification (90% of use cases)
│   ├── create_library.nf         # Library creation from FASTA
│   └── full_pipeline.nf          # Multi-round pipeline with tuning
│
├── modules/                       # Reusable process modules
│   ├── quantify.nf               # MS quantification process
│   ├── library.nf                # Library generation process
│   └── tune.nf                   # Model tuning process
│
├── configs/                       # Example configurations
│   ├── simple_quant.yaml         # Example: simple quantification
│   ├── library_creation.yaml     # Example: library creation
│   └── full_pipeline.yaml        # Example: full multi-round pipeline
│
└── bin/                           # Utility scripts
    └── check_setup.sh            # Verify environment setup
```

## Key Design Decisions

### 1. Modular Architecture
- **3 workflows** for different use cases
- **3 reusable modules** that can be composed
- **Clear separation** between workflow logic and process execution

### 2. Flexible Entry Points

#### Workflow 1: quantify_only.nf (Most Common)
**When to use:** You have an existing spectral library and need to quantify samples.

**What it does:**
- Takes existing library
- Quantifies one or more samples
- Automatically applies `.d` file parameters (`--mass-acc 15/15`)

**Typical usage:**
```bash
nextflow run karlssoc/diann-wf -params-file configs/simple_quant.yaml -profile slurm
```

#### Workflow 2: create_library.nf
**When to use:** You need to create a new spectral library from a FASTA file.

**What it does:**
- Generates spectral library from FASTA
- Optionally uses pre-tuned models
- Outputs reusable library for future quantifications

**Typical usage:**
```bash
nextflow run karlssoc/diann-wf/workflows/create_library.nf -params-file configs/library_creation.yaml -profile slurm
```

#### Workflow 3: full_pipeline.nf (Advanced)
**When to use:** You need comprehensive analysis with model optimization.

**What it does:**
- Round 1: Generate library (default) → Quantify
- Tune: Fine-tune RT/IM/FR models
- Round 2: Generate library (RT+IM) → Quantify
- Round 3: Generate library (RT+IM+FR) → Quantify

**Typical usage:**
```bash
nextflow run karlssoc/diann-wf/workflows/full_pipeline.nf -params-file configs/full_pipeline.yaml -profile slurm
```

### 3. Smart Parameter Handling

**Automatic file-type detection:**
- `.d` files → adds `--mass-acc 15 --mass-acc-ms1 15`
- `.raw` files → uses defaults
- `.mzML` files → uses defaults

**Container version flexibility:**
- Default: `2.3.1` (latest with FR tuning)
- Configurable per workflow or round
- Pulled from `quay.io/karlssoc/diann`

**SLURM integration:**
- Automatic resource allocation by process type
- Queue and account configuration
- Optional node selection

### 4. Human-Friendly Configuration

All parameters in simple YAML files:
```yaml
library: 'path/to/library.speclib'
fasta: 'path/to/fasta'
samples:
  - id: 'sample1'
    dir: 'input/sample1'
    file_type: 'd'
threads: 60
slurm_account: 'my_username'
```

### 5. Production-Ready Features

✓ **Resume capability** - Restart failed runs without recomputation
✓ **Execution reports** - Timeline, resource usage, DAG visualization
✓ **Error handling** - Automatic retries, clear error messages
✓ **Parallel execution** - Samples processed concurrently
✓ **Dependency tracking** - Automatic handling of complex workflows
✓ **Container isolation** - Reproducible environments

## Comparison to Your Existing Scripts

### Your Current Approach (Remote Server)
```bash
# Multiple manual scripts
run_diann3-r1a.sh     # Round 1
tune-2.3.1-ttht-p2.sh # Tuning
run_diann3-r2a.sh     # Round 2
run_diann3-r3a.sh     # Round 3
```

**Limitations:**
- Manual dependency management
- Hard to modify parameters
- No automatic retry on failure
- Difficult to track what ran
- Can't easily parallelize samples

### New Nextflow Approach
```bash
# Single command for entire pipeline
nextflow run karlssoc/diann-wf/workflows/full_pipeline.nf -params-file configs/my_config.yaml -profile slurm
```

**Advantages:**
- ✓ Automatic dependency tracking
- ✓ Easy parameter modification (YAML file)
- ✓ Automatic retry on failure (`-resume`)
- ✓ Complete execution reports
- ✓ Automatic parallelization
- ✓ Can skip/enable rounds flexibly

## How Your Remote Scripts Map to Workflows

### Example 1: run_diann3-r1b.sh → quantify_only.nf
Your script quantifies samples with existing library.

**Old way:**
```bash
./run_diann3-r1b.sh  # Hard-coded paths and parameters
```

**New way:**
```yaml
# configs/r1b_equivalent.yaml
library: 'idmapping_2025_11_20.predicted.speclib'
fasta: 'idmapping_2025_11_20.fasta'
samples:
  - {id: 'hfx-30SPD', dir: 'input/hfx-30SPD', file_type: 'raw'}
  - {id: 'hfx-50SPD', dir: 'input/hfx-50SPD', file_type: 'raw'}
```

```bash
nextflow run karlssoc/diann-wf -params-file configs/r1b_equivalent.yaml -profile slurm
```

### Example 2: Your Multi-Round Pipeline → full_pipeline.nf
Your scripts: r1a.sh → tune-2.3.1.sh → r2a.sh → r3a.sh

**Old way:**
```bash
./run_diann3-r1a.sh   # Wait for completion
./tune-2.3.1-ttht-p2.sh  # Wait for completion
./run_diann3-r2a.sh   # Wait for completion
./run_diann3-r3a.sh   # Wait for completion
```

**New way:**
```yaml
# configs/multi_round.yaml
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
```

```bash
# Single command, automatic dependency handling
nextflow run karlssoc/diann-wf/workflows/full_pipeline.nf -params-file configs/multi_round.yaml -profile slurm
```

## Getting Started

### 1. Verify Setup
```bash
./bin/check_setup.sh
```

### 2. Quick Test
```bash
# Copy and edit example config
cp configs/simple_quant.yaml configs/my_test.yaml
nano configs/my_test.yaml  # Update paths

# Test locally
nextflow run karlssoc/diann-wf -params-file configs/my_test.yaml -profile test
```

### 3. Production Run
```bash
# Submit to SLURM
nextflow run karlssoc/diann-wf -params-file configs/my_test.yaml -profile slurm
```

### 4. Check Results
```bash
ls -lh results/
ls -lh results/pipeline_info/  # Execution reports
```

## Common Operations

### Resume Failed Run
```bash
nextflow run karlssoc/diann-wf -params-file configs/my_config.yaml -profile slurm -resume
```

### Override Single Parameter
```bash
nextflow run karlssoc/diann-wf \
  -params-file configs/my_config.yaml \
  --threads 40 \
  --diann_version 2.2.0 \
  -profile slurm
```

### Run Only Specific Rounds
```bash
# Skip R1, only run R2 and R3 with existing tuned models
nextflow run karlssoc/diann-wf/workflows/full_pipeline.nf \
  -params-file configs/full_pipeline.yaml \
  --run_r1 false \
  -profile slurm
```

## Next Steps

1. **Read QUICKSTART.md** for step-by-step tutorial
2. **Read README.md** for comprehensive documentation
3. **Copy and modify** example configs for your experiments
4. **Test locally** before SLURM submission
5. **Review execution reports** to optimize resources

## Key Files to Customize

1. **configs/*.yaml** - Your experimental parameters
2. **nextflow.config** - SLURM resources (if defaults don't work)
3. **modules/*.nf** - DIANN parameters (advanced users)

## Support Resources

- **QUICKSTART.md** - Quick tutorial
- **README.md** - Complete documentation
- **Nextflow docs** - https://www.nextflow.io/docs/latest/
- **DIANN docs** - https://github.com/vdemichev/DiaNN

## Advantages Summary

| Feature | Old Scripts | New Nextflow |
|---------|-------------|--------------|
| Dependency tracking | Manual | Automatic |
| Parameter management | Hard-coded | YAML configs |
| Parallelization | Manual loops | Automatic |
| Resume failed runs | Rerun everything | Resume from failure |
| Execution reports | None | Comprehensive |
| Version control | Script copies | Config files |
| Flexibility | Low | High |
| Learning curve | None | Moderate |

## When to Use Each Workflow

| Workflow | When to Use | Typical Duration |
|----------|-------------|------------------|
| quantify_only.nf | Daily quantification with existing library | Minutes-hours |
| create_library.nf | New organism or updated FASTA | 1-4 hours |
| full_pipeline.nf | Publication-quality comprehensive analysis | Several hours |

---

**Created:** December 2024
**Version:** 1.0.0
**Status:** Production ready
