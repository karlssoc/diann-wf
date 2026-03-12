# Quantify Parameters Reference

Parameters for the `quantify_only` entry point (`modules/quantify.nf`).

## Required Parameters

| YAML Parameter | DIA-NN Flag | Description |
|---|---|---|
| `library` | `--lib` | Path to spectral library (`.predicted.speclib` or `.parquet`) |
| `fasta` | `--fasta` | Path to FASTA protein database |
| `samples` | `--dir` / `--dir-all` | List of sample definitions (see [Sample Definition](#sample-definition)) |
| `outdir` | `--out` | Output directory (results written to `outdir/sample_id/`) |

## Sample Definition

Each entry under `samples:` supports:

| Field | Description | Default |
|---|---|---|
| `id` | Sample identifier (used as output subdirectory name) | required |
| `dir` | Path to directory containing MS files | required |
| `file_type` | File type: `d` (Bruker .d), `raw` (Thermo .raw), `mzML` | required |
| `recursive` | If `true`, uses `--dir-all` (search subdirectories); `false` uses `--dir` | `false` |

> **Note:** Bruker `.d` files automatically use `--mass-acc 15 --mass-acc-ms1 15` unless `mass_acc` / `mass_acc_ms1` are set explicitly.

## Quantification Parameters

| YAML Parameter | DIA-NN Flag | Default | Description |
|---|---|---|---|
| `pg_level` | `--pg-level` | `1` | Protein group level: `1` = proteins, `0` = genes |
| `qvalue` | `--qvalue` | `0` | Precursor q-value threshold; `0` uses DIA-NN default (0.01) |
| `mass_acc` | `--mass-acc` | `null` | MS2 mass accuracy (ppm); `null` = auto (15 for Bruker `.d`, otherwise DIA-NN auto) |
| `mass_acc_ms1` | `--mass-acc-ms1` | `null` | MS1 mass accuracy (ppm); `null` = auto (15 for Bruker `.d`, otherwise DIA-NN auto) |
| `mass_acc_cal` | `--mass-acc-cal` | `null` | Mass accuracy calibration threshold (ppm); `null` = DIA-NN auto |
| `smart_profiling` | `--smart-profiling` | `false` | Enable smart profiling for quantification |
| `individual_mass_acc` | `--individual-mass-acc` | `false` | Per-file mass accuracy calibration. **Warning:** causes ~12% systematic intensity decrease |
| `individual_windows` | `--individual-windows` | `false` | Per-file RT windows (useful for multi-batch data) |
| `matrices` | `--matrices` | `true` | Generate quantification matrix TSV files |
| `mbr` | `--reanalyse` | `false` | Match-between-runs in identification stage |
| `mbr_final` | `--reanalyse` | `true` | Match-between-runs in final quantification stage |

## Batch Correction Parameters

| YAML Parameter | DIA-NN Flag | Default | Description |
|---|---|---|---|
| `ref_library` | `--ref` | `null` | Reference library for batch calibration (small library from reference sample) |
| `individual_windows` | `--individual-windows` | `false` | Per-run RT windows instead of global windows |
| `individual_mass_acc` | `--individual-mass-acc` | `false` | Per-run mass accuracy calibration |

## Ultrafast Mode

Set `ultrafast: true` to enable. Reduces runtime by ~50% at the cost of sensitivity.

| DIA-NN Flag | Value | Effect |
|---|---|---|
| `--min-corr` | `2.0` | More aggressive correlation filtering |
| `--time-corr-only` | — | Simplified correlation (time-domain only) |
| `--extracted-ms1` | — | Use extracted MS1 only |
| `--min-cal` | `500` | Reduced calibration requirements |
| `--min-class` | `1000` | Reduced classification requirements |
| `--pre-filter` | — | Apply pre-filtering before full analysis |
| `--rt-window-mul` | `1.7` | Wider RT windows |
| `--rt-window-factor` | `100` | RT window scaling factor |

## Runtime / Resource Parameters

| YAML Parameter | Description | Default |
|---|---|---|
| `threads` | CPU threads per job | `60` |
| `parallel_mode` | Split into 2×30 core jobs for concurrent sample processing | `true` |
| `time_base_hours` | Base SLURM time allocation (hours) | `2` |
| `time_per_file_minutes` | Additional time per MS file (minutes) | `10` |
| `diann_version` | DIA-NN version | `2.3.2` |
| `diann_binary` | Explicit path to DIA-NN binary; `null` = auto-computed from `diann_version` | `null` |

> **Time formula:** `ceil((time_base_hours × 60 + file_count × time_per_file_minutes) / 60)` hours.
> Ultrafast mode reduces total by 50%.

## SLURM Parameters

| YAML Parameter | Description | Default |
|---|---|---|
| `slurm_account` | SLURM account/username | — |
| `slurm_queue` | SLURM partition | `work` |
| `slurm_nodelist` | Pin to specific node (e.g., `alap759`) | — |

## Always-On DIA-NN Flags

These are always passed regardless of config:

| DIA-NN Flag | Value | Description |
|---|---|---|
| `--threads` | `task.cpus` | Thread count from Nextflow resource allocation |
| `--verbose` | `1` | Logging verbosity |
| `--temp` | `temp_diann` | Temp directory (prevents parallel job interference) |
| `--out` | `report.parquet` | Main output report |
| `--out-lib` | `out-lib.parquet` | Output library |
| `--reannotate` | — | Auto-added when library is `.parquet` format |

## Example Configs

- [`configs/quantify/basic.yaml`](../configs/quantify/basic.yaml) — standard quantification
- [`configs/quantify/batch_correction.yaml`](../configs/quantify/batch_correction.yaml) — multi-batch with reference calibration
- [`configs/quantify/ultrafast.yaml`](../configs/quantify/ultrafast.yaml) — fast mode
- [`configs/quantify/smb_storage.yaml`](../configs/quantify/smb_storage.yaml) — network (SMB) input data
