# hystar-metadata — Bruker HyStar Acquisition Metadata Extraction

Extracts acquisition metadata from Bruker TimsTOF `.d` directories and writes a
sorted CSV table. Useful for tracking run order, linking HyStar `SampleID` names
to DIA-NN output files, and auditing acquisitions before or after quantification.

## Background

Bruker HyStar creates a `.d` directory for each acquisition. Inside every `.d`
folder, `HyStarMetadata.xml` stores the acquisition timestamp, the original
Windows file path, and the user-defined `SampleID` set in HyStar. The `.d`
directory name on disk encodes `{SampleID}_{position}_{injection-count}` and
differs from the `SampleID` (which has no suffix).

Example:
- HyStar `SampleID`: `LJH_T2509_1000_HeLa100ng_1`
- `.d` directory: `LJH_T2509_1000_HeLa100ng_1_S1-H1_1_5404.d`

## Output

CSV table sorted by `CreationDateTime` with columns:

| Column | Source | Description |
|--------|--------|-------------|
| `YamlSampleId` | YAML `samples[].id` | Logical sample group from the workflow config |
| `SampleID` | `HyStarMetadata.xml` | HyStar acquisition name (no position/injection suffix) |
| `CreationDateTime` | `HyStarMetadata.xml` | ISO 8601 acquisition timestamp with timezone |
| `FileName` | `HyStarMetadata.xml` | `.d` directory name only (no path) |
| `WindowsPath` | `HyStarMetadata.xml` | Full original Windows path from HyStar |
| `LocalPath` | filesystem | Absolute local path to the `.d` directory |

## Prerequisites

System Python path (auto-detected if PyYAML is available):
- Python 3.8+
- `pyyaml` — `pip install pyyaml`

Container path (no local install required):
- Apptainer, Singularity, or Docker
- Container: `quay.io/karlssoc/diannwf-python:1.0`

## Usage

### Standalone (command line)

```bash
# Auto-detects PyYAML → falls back to container if missing
hystar-metadata params.yaml

# Force container execution (recommended on HPC without PyYAML)
hystar-metadata params.yaml --container

# Override output directory
hystar-metadata params.yaml --outdir results/metadata

# Custom output filename
hystar-metadata params.yaml --output run_metadata.csv

# Force system Python (skip container detection)
hystar-metadata params.yaml --no-container
```

Container runtime is auto-detected in priority order:
`apptainer` → `singularity` → `docker`

### Input YAML format

The script reads `samples` entries with `file_type: 'd'`. Non-`d` entries are
silently skipped. The `dir` path is resolved relative to the current working
directory (or `--basedir` if specified).

```yaml
samples:
  - id: 'hela_qc'
    dir: 'input/raw/d'
    file_type: 'd'
    recursive: false      # Optional: search subdirectories (default: false)

  - id: 'plasma'
    dir: 'input/plasma/d'
    file_type: 'd'
    recursive: true       # Scan subdirectories for nested .d folders

outdir: 'results/quantification'
```

### Nextflow module

For automated post-quantification runs, include the module in a workflow:

```groovy
include { EXTRACT_HYSTAR_METADATA } from './modules/extract_hystar_metadata'

// Pass the params YAML file as input
EXTRACT_HYSTAR_METADATA(file(params_yaml_path))

// Output: hystar_metadata.csv published to params.outdir
```

The module uses `executor = 'local'` (runs on the head node, not in a SLURM job)
and the `quay.io/karlssoc/diannwf-python:1.0` container.

## Options reference

```
hystar-metadata <params.yaml> [options]

Options:
  --outdir DIR      Override output directory (default: outdir from YAML)
  --output FILE     Output CSV filename (default: hystar_metadata.csv)
  --basedir DIR     Base directory for resolving relative 'dir' paths
                    (default: CWD; set to launchDir when called from Nextflow)
  --container       Force container execution (apptainer/singularity/docker)
  --no-container    Force system Python (skip container detection)
```

## Examples

### HPC usage (kraken / COSMOS)

After `nextflow pull karlssoc/diann-wf`, the scripts are in
`~/.nextflow/assets/karlssoc/diann-wf/bin/`. Add to PATH or call directly:

```bash
~/.nextflow/assets/karlssoc/diann-wf/bin/hystar-metadata \
    configs/quantify/hela.yaml \
    --container \
    --outdir results/metadata
```

Or after adding the bin directory to PATH:
```bash
export PATH="$HOME/.nextflow/assets/karlssoc/diann-wf/bin:$PATH"
hystar-metadata configs/quantify/hela.yaml --container
```

### Output example

```
YamlSampleId,SampleID,CreationDateTime,FileName,WindowsPath,LocalPath
hela_qc,SK_T2602_1000_DDA_HeLa_260210_1,2026-02-10T19:12:46+01:00,SK_T2602_1000_DDA_HeLa_260210_1_S1-H12_1_5299.d,D:\Data\HeLa\SK_T2602_1000_DDA_HeLa_260210_1_S1-H12_1_5299.d,/srv/data1/karlssoc/projects/tt/hela-qc/input/raw/d/SK_T2602_1000_DDA_HeLa_260210_1_S1-H12_1_5299.d
hela_qc,LJH_T2509_1000_HeLa100ng_1,2026-02-16T17:53:14+01:00,LJH_T2509_1000_HeLa100ng_1_S1-H1_1_5404.d,D:\Data\HeLa\LJH_T2509_1000_HeLa100ng_1_S1-H1_1_5404.d,/srv/data1/karlssoc/projects/tt/hela-qc/input/raw/d/LJH_T2509_1000_HeLa100ng_1_S1-H1_1_5404.d
```

## Notes

- `.d` directories without `HyStarMetadata.xml` are skipped with a warning
- Sample dirs listed in the YAML that do not exist on disk are skipped with a warning
- Rows are sorted by `CreationDateTime` (acquisition order)
- `SampleID` in HyStar may contain spaces (e.g. `new emittor 2`); these are
  preserved in the CSV. The corresponding `.d` directory name on Linux may use
  underscores in place of spaces
