# DIANN Nextflow Workflows

Modular Nextflow workflows for DIA-NN mass spectrometry analysis with SLURM integration.

## Overview

Available entry points (via `nextflow run karlssoc/diann-wf -entry <NAME>`):

| Entry | Description | When to use |
|-------|-------------|-------------|
| **`QUANTIFY_FASTA_SUBSET`** | **Full FASTA → Pass 1 → subset FASTA → new speclib → Pass 2** | **Recommended for most cohorts** |
| `PRESEARCH_AND_QUANTIFY` | Full FASTA → Pass 1 → subset library (parquet) → Pass 2 | Alternative; no new library generation |
| `LIBRARY_AND_QUANTIFY` | Generate library from FASTA + quantify (single pass) | Simple all-in-one |
| `quantify_only` | Quantify with an existing spectral library | Existing library available |
| `create_library` | Generate spectral library from FASTA only | Library generation step only |
| `repredict_library` | Repredict existing library with new/tuned models | Transfer library to new instrument |
| `tune_models` | Tune RT/IM/FR prediction models | Model optimization |
| `convert_library` | Convert `.speclib` → `.parquet` | Library format conversion |

Development/comparison workflows (run directly, not via `main.nf -entry`):
`compare_libraries.nf`, `compare_with_models.nf`, `evaluate_models.nf`, `infindia_presearch_only.nf`, `tune_only.nf`

## Quick Start

### Recommended: FASTA Subset + Quantification

Two-pass workflow that reduces the search space by subsetting the FASTA to proteins
detected in pass 1, then generating a fresh spectral library from the subset. This
improves FDR calibration and makes pass 2 ~5x faster.

```bash
# Pull the workflow from GitHub (first time only)
nextflow pull karlssoc/diann-wf

# Edit the config file with your paths
nano configs/workflows/quantify_fasta_subset.yaml

# Run on SLURM (background)
nextflow -bg run karlssoc/diann-wf -entry QUANTIFY_FASTA_SUBSET \
  -params-file configs/workflows/quantify_fasta_subset.yaml \
  -profile slurm

# Or use the wrapper script
diann-wf QUANTIFY_FASTA_SUBSET configs/workflows/quantify_fasta_subset.yaml slurm
```

**Output:**
```
results/
├── library/<library_name>.predicted.speclib       # Full library (pass 1)
├── pass1/<sample>/report-first-pass.parquet        # Pass 1 results
├── subset_fasta/subset.fasta                       # Subset FASTA
├── library/subset/<library_name>_subset.predicted.speclib  # Subset library
├── <sample>/report.parquet                         # Final quantification results
└── pipeline_info/                                  # Nextflow execution reports
```

### Simple Quantification (Existing Library)

```bash
nextflow -bg run karlssoc/diann-wf -entry quantify_only \
  -params-file configs/quantify/basic.yaml -profile slurm
```

### Create Library

```bash
nextflow -bg run karlssoc/diann-wf -entry create_library \
  -params-file configs/library/standard.yaml -profile slurm
```

## Using the Wrapper Script

The `bin/diann-wf` wrapper simplifies execution for non-Nextflow users:

```bash
diann-wf QUANTIFY_FASTA_SUBSET config.yaml slurm        # Production
diann-wf quantify_only quant.yaml docker -resume          # With extra args
diann-wf list                                              # Show all workflows
```

## Using Pre-Trained Models

Pre-trained DIA-NN models for common instrument/LC/method combinations are available
in the [models/](models/) directory.

### Available Presets

See [models/README.md](models/README.md) for the current list of presets.

Example presets:
- `ttht-evos-30spd` - Bruker timsTOF HT + Evosep 30 SPD
- `hfx-vneo-30spd` - Thermo HFX + Vanquish Neo µPAC

### Quick Example

```yaml
# In your config YAML
model_preset: 'ttht-evos-30spd'
tuning_mode: 'skip'   # Use preset directly, no tuning step
```

Or with explicit paths:
```yaml
tokens: 'path/to/dict.txt'
rt_model: 'path/to/tuned_rt.pt'
im_model: 'path/to/tuned_im.pt'
fr_model: 'path/to/tuned_fr.pt'
```

### Adding Your Own Models

```bash
# Collect models from DIA-NN tuning output
./bin/collect_models.sh -s results/tuning -n my-instrument-method

# Edit metadata
nano models/my-instrument-method/metadata.yaml

# Commit to repository
git add models/my-instrument-method
git commit -m "feat: Add models for my-instrument-method"
```

See [models/README.md](models/README.md) for contribution guidelines.

## Requirements

- Nextflow >= 21.04.0
- Container runtime (choose one):
  - Singularity/Apptainer (recommended for HPC)
  - Docker or OrbStack (for local development)
  - Podman
- Access to DIANN containers: `quay.io/karlssoc/diann`

Available DIANN versions: `2.3.2` (default), `2.3.1`, `2.3.0-beta`, `2.2.0`, `1.8.1`

## Execution Profiles

| Profile | Environment | Cores | Container | Local Disk |
|---------|------------|-------|-----------|------------|
| `standard` | Local | Variable | Singularity | No |
| `docker` | Local | Variable | Docker | No |
| `podman` | Local | Variable | Podman | No |
| `slurm` | Generic HPC | 60 (default) | Singularity | No |
| `cosmos` | LUNARC HPC | 48 (fixed) | Singularity | Yes ($SNIC_TMP) |
| `docker_slurm` | Generic HPC | Variable | Docker | No |
| `podman_slurm` | Generic HPC | Variable | Podman | No |

### COSMOS HPC Profile

The `cosmos` profile is optimized for the [LUNARC COSMOS cluster](https://www.lunarc.lu.se/systems/cosmos):

- **48 cores** per node (AMD Milan) - automatically configured
- **Local disk staging** - MS files copied to 2 TB node-local disk for 10-50x faster I/O
- **Optimal parallel mode** - 2×24 core jobs for better throughput
- **SLURM tuning** - Timeouts optimized for shared cluster

```bash
nextflow -bg run karlssoc/diann-wf -entry QUANTIFY_FASTA_SUBSET \
  -params-file configs/workflows/quantify_fasta_subset.yaml \
  -profile cosmos
```

Required config:
```yaml
slurm_account: 'YOUR_LUNARC_PROJECT'
slurm_queue: 'lu'
```

### ARM/Apple Silicon Warning

**The DIANN container is x86-64 only.** On ARM Macs, the container runs via Rosetta 2
emulation which can produce different scientific results (lower ID rates, altered
quantification). Use native x86-64 hardware or HPC for production runs.

## Detailed Workflow Descriptions

### QUANTIFY_FASTA_SUBSET (Recommended)

Two-pass search space reduction via FASTA subsetting:

1. **Generate library** from full FASTA
2. *(Optional)* **Auto-generate calibration ref library** (`ref_n_proteins` param)
   → Presearch N files ultrafast → top-N proteins → small speclib used as `--ref`
   for faster RT/IM calibration in both passes (recommended for large FASTA files)
3. **Pass 1:** Quantify all samples, full library, MBR enabled
   → `report-first-pass.parquet` = union of per-run 1% FDR IDs across all samples
4. **Subset FASTA** to Protein.Groups detected in pass 1
5. **Generate new library** from subset FASTA (native speclib, no `--reannotate`)
6. **Pass 2:** Quantify all samples, subset library, MBR enabled

**Advantages over PRESEARCH_AND_QUANTIFY:**
- Fresh speclib from subset FASTA: full predicted spectral quality preserved
- Native speclib used as-is in pass 2 (no `--reannotate`)
- ~78% smaller library: faster pass 2, less decoy competition, better FDR calibration
- Total time ≈ 1.2x a standard single-pass run

**Calibration ref library parameters** (add to config to enable):
```yaml
ref_n_proteins: 300      # proteins in ref library (recommended: 300)
ref_n_samples: 1         # batches to presearch (default: 2)
ref_presearch_files: 5   # files per batch (default: 5; 0 = all)
```

Config file: [configs/workflows/quantify_fasta_subset.yaml](configs/workflows/quantify_fasta_subset.yaml)

```yaml
fasta: '/path/to/protein.fasta'
samples:
  - id: 'sample1'
    dir: '/path/to/ms_data/sample1'
    file_type: 'dia'
    recursive: false
  - id: 'sample2'
    dir: '/path/to/ms_data/sample2'
    file_type: 'dia'
    recursive: false
library_name: 'generated_lib'
outdir: 'results/quantify_fasta_subset'
diann_version: '2.3.2'
threads: 48
slurm_account: 'YOUR_PROJECT'
slurm_queue: 'lu'
```

### PRESEARCH_AND_QUANTIFY

Alternative two-pass workflow that subsets the library parquet (not the FASTA):

1. Quantify N presearch samples against full library (Pass 1)
2. Subset library to identified Protein.Groups
3. Quantify all samples against subset library (Pass 2)

**When to use:** Faster if you can select a representative presearch subset.
**Disadvantage:** Uses `--reannotate` in pass 2 (library intensities/RTs reset).

Config file: [configs/workflows/presearch_and_quantify.yaml](configs/workflows/presearch_and_quantify.yaml)

### LIBRARY_AND_QUANTIFY

Single-pass: generate library from FASTA, then quantify all samples.

```bash
nextflow -bg run karlssoc/diann-wf -entry LIBRARY_AND_QUANTIFY \
  -params-file configs/workflows/library_and_quantify.yaml -profile slurm
```

### quantify_only

Simple quantification when you already have a spectral library.

```yaml
# configs/quantify/basic.yaml
library: '/path/to/library.predicted.speclib'
fasta: '/path/to/protein.fasta'
samples:
  - id: 'exp01'
    dir: 'input/exp01'
    file_type: 'd'
outdir: 'results/exp01'
diann_version: '2.3.2'
threads: 60
slurm_account: 'my_username'
```

```bash
nextflow -bg run karlssoc/diann-wf -entry quantify_only \
  -params-file configs/quantify/basic.yaml -profile slurm
```

**Output:**
```
results/
├── sample1/
│   ├── report.parquet          # Main quantification results
│   ├── out-lib.parquet         # Output library
│   ├── *.tsv                   # Matrix files (if matrices: true)
│   └── diann.log
└── pipeline_info/
```

### create_library

Generate a spectral library from a FASTA file.

```bash
nextflow -bg run karlssoc/diann-wf -entry create_library \
  --fasta mydata.fasta \
  --library_name mylib \
  --outdir results/library \
  -profile slurm
```

### repredict_library

Repredict an existing library with current/tuned models. Useful for transferring
a library to a different instrument or updating predictions.

```yaml
# configs/library/repredict.yaml
fasta: '/path/to/protein.fasta'
input_library: '/path/to/existing/library.predicted.speclib'
library_name: 'repredicted_lib'
outdir: 'results/repredicted_library'
```

```bash
nextflow -bg run karlssoc/diann-wf/workflows/repredict_library.nf \
  -params-file configs/library/repredict.yaml -profile slurm
```

## Configuration

### Sample Definition

```yaml
samples:
  - id: 'sample1'
    dir: 'input/sample1'
    file_type: 'd'          # Bruker .d files
    recursive: false

  - id: 'sample2'
    dir: 'input/sample2'
    file_type: 'raw'        # Thermo .raw files

  - id: 'sample3'
    dir: 'input/sample3'
    file_type: 'mzML'
```

### File Type Parameters

| File Type | Parameters Applied |
|-----------|-------------------|
| `.d` (Bruker) | `--mass-acc 15 --mass-acc-ms1 15` (configurable) |
| `.raw` (Thermo) | `--mass-acc 15 --mass-acc-ms1 5` (configurable; empirically +5% IDs vs auto) |
| `.mzML` | DIA-NN auto-calibration |
| `.dia` | DIA-NN auto-calibration |

### Key Parameters

```yaml
# Common
diann_version: '2.3.2'
threads: 60
outdir: 'results'
slurm_account: 'username'
slurm_queue: 'work'
parallel_mode: false        # Split into 2x30-core jobs

# Quantification
qvalue: 0                   # 0 = DIA-NN default (1% FDR)
pg_level: 1                 # 1=proteins, 0=genes
# mass_acc: 15             # MS2 ppm. Thermo HFX/Orbitrap: 15 (+5% IDs vs auto). Bruker .d: omit (default 15).
# mass_acc_ms1: 5          # MS1 ppm. Thermo HFX/Orbitrap: 5 (+5% IDs vs auto). Bruker .d: omit (default 15).
individual_mass_acc: false  # No ID benefit; causes ~12% intensity decrease — leave false
smart_profiling: true
matrices: true
mbr: false                  # MBR for identification stage
mbr_final: true             # MBR for final quantification

# Library generation
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

### SLURM Configuration

Resource allocation by process type:
- **Tuning:** 10 CPUs, 10 GB RAM, 2h
- **Library:** 30-60 CPUs, 20-30 GB, 4h
- **Quantification:** 30-60 CPUs, dynamic RAM, dynamic time

## Remote Storage (SMB/NFS)

The workflow reads input data from any mounted filesystem:

```yaml
library: '/mnt/imp_arch/libraries/mylib.predicted.speclib'
fasta: '/mnt/imp_arch/fasta/proteome.fasta'
samples:
  - id: 'sample1'
    dir: '/mnt/imp_arch/raw_data/sample1'
    file_type: 'd'
outdir: '/scratch/results/quantification'  # Local output is faster
```

**Performance tip:** Use `-profile cosmos` for automatic local disk staging (10-50x
faster for Bruker `.d` files).

## Advanced Features

### Background Execution

Always use `-bg` for SLURM to persist through terminal disconnections:

```bash
nextflow -bg run karlssoc/diann-wf -entry QUANTIFY_FASTA_SUBSET \
  -params-file config.yaml -profile slurm
```

Monitor:
```bash
tail -f .nextflow.log
squeue -u $USER
nextflow log
```

### Resume Failed Runs

```bash
nextflow -bg run karlssoc/diann-wf -params-file config.yaml -resume -profile slurm
```

### Override DIA-NN Version

```bash
nextflow run karlssoc/diann-wf -entry quantify_only \
  -params-file config.yaml --diann_version 2.2.0 -profile slurm
```

## Execution Reports

Nextflow generates reports in `results/pipeline_info/`:

- `execution_timeline.html` - Timeline of process execution
- `execution_report.html` - Resource usage statistics
- `execution_trace.txt` - Detailed execution trace
- `pipeline_dag.dot` - Workflow DAG

## Project Structure

```
diann-wf/
├── main.nf                          # Single entry point (-entry flag)
├── workflows/                       # Workflow definitions
│   ├── quantify_fasta_subset.nf     # FASTA subset + quantify (recommended)
│   ├── presearch_and_quantify.nf    # Library subset + quantify
│   ├── library_and_quantify.nf      # Library generation + quantify
│   ├── quantify_only.nf             # Quantify with existing library
│   ├── create_library.nf            # Library generation
│   ├── repredict_library.nf         # Repredict library with new models
│   ├── convert_library.nf           # Convert .speclib to .parquet
│   ├── tune_only.nf                 # Tune models only
│   ├── iterative_quant.nf           # Iterative quant (experimental)
│   ├── compare_libraries.nf         # Compare default vs tuned libraries
│   ├── compare_with_models.nf       # Compare default vs preset models
│   └── evaluate_models.nf           # Multi-preset accuracy comparison
├── modules/                         # Reusable process modules
├── configs/                         # Configuration templates
│   ├── workflows/                   # Multi-step workflow configs
│   ├── quantify/                    # Single quantify configs
│   ├── library/                     # Library generation configs
│   └── tune/                        # Model tuning configs
├── models/                          # Pre-trained model presets
├── bin/                             # Utility scripts
│   ├── diann-wf                     # Workflow runner wrapper
│   ├── hystar-metadata              # Bruker HyStar metadata extraction (see docs/hystar-metadata.md)
│   ├── compare_pg_matrices.py       # PG matrix comparison CLI
│   └── collect_models.sh            # Organize tuning outputs
└── nextflow.config                  # Profiles, resources, param defaults
```

## Utility Scripts

| Script | Description | Docs |
|--------|-------------|------|
| `bin/diann-wf` | Workflow runner wrapper (abstracts Nextflow for end users) | — |
| `bin/hystar-metadata` | Extract Bruker HyStar acquisition metadata from `.d` directories | [docs/hystar-metadata.md](docs/hystar-metadata.md) |
| `bin/compare_pg_matrices.py` | Compare two DIA-NN `pg_matrix.tsv` files for quantitative agreement | — |
| `bin/collect_models.sh` | Organize DIA-NN tuning outputs into model preset directories | — |

## Deployment

### GitHub

```bash
# Pull latest
nextflow pull karlssoc/diann-wf

# Run from GitHub
nextflow -bg run karlssoc/diann-wf -entry QUANTIFY_FASTA_SUBSET \
  -params-file configs/workflows/quantify_fasta_subset.yaml -profile cosmos

# Pin a version for reproducibility
nextflow run karlssoc/diann-wf -r v1.0.0 \
  -params-file config.yaml -profile cosmos
```

## Troubleshooting

### Check Workflow Status

```bash
nextflow log
nextflow log <run_name> -f status,name,exit,duration
```

### Test Locally Before SLURM

```bash
nextflow run karlssoc/diann-wf -entry QUANTIFY_FASTA_SUBSET \
  -params-file configs/workflows/quantify_fasta_subset.yaml \
  -profile standard
```

### Container Issues

```bash
# Pre-pull containers
singularity pull diann_2.3.2.sif docker://quay.io/karlssoc/diann:2.3.2
```

## TODO

- [ ] Test `-profile cosmos` on COSMOS cluster with real data
- [ ] Integration with storage (SMB, Swestore, OpenBIS, seqera)
- [x] `.speclib` to `.parquet` — `workflows/convert_library.nf` (verified byte-identical quantification output)
- [ ] Restructure MS profiles (ttht-evosep-30SPD, hfx-vneo-24SPD) using sets of tuned parameters
- [ ] Semantics: `Sample` → `Batch`
- [ ] Support multiple FASTA files per sample/batch
- [ ] No IM prediction for Thermo raw
- [ ] Only use MS files matching requested type (ignore others in same dir)
- [ ] Maybe rename `slurm` profile → `kraken`
- [ ] Tuning DIA-NN FR for HFX has no added benefit for external validation; results worse than original

## Support

- Nextflow docs: https://www.nextflow.io/docs/latest/
- DIA-NN docs: https://github.com/vdemichev/DiaNN
- Execution logs: `results/pipeline_info/`

## License

This workflow system is provided as-is for research use.
