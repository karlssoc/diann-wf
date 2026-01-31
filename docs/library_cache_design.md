# Spectral Library Caching Design

## Problem

Library generation (`GENERATE_LIBRARY`) is a slow, deterministic process. Given identical inputs (FASTA + parameters + DIA-NN version), the output is always the same. Currently, we regenerate libraries even when an identical one already exists, wasting compute time.

## Proposed Solution

Use Nextflow's `storeDir` directive to implement local caching of predicted spectral libraries. When a matching library exists in the cache, Nextflow skips execution entirely.

## Cache Location

```
~/.diann_cache/
  libraries/
    <hash>/
      library.predicted.speclib
      params.yaml           # Provenance tracking
```

Configurable via `params.library_cache` with sensible default:

```groovy
params.library_cache = "${System.getenv('HOME')}/.diann_cache/libraries"
```

## Cache Key Design

The cache key (hash) must uniquely identify a library based on all inputs that affect the output.

### Components

| Component | Source | Notes |
|-----------|--------|-------|
| FASTA checksum | `fasta.md5()` | Content-based, not path |
| DIA-NN version | `params.diann_version` | e.g., "2.3.1" |
| Peptide length | `params.min_pep_len`, `params.max_pep_len` | |
| Precursor m/z | `params.min_pr_mz`, `params.max_pr_mz` | |
| Precursor charge | `params.min_pr_charge`, `params.max_pr_charge` | |
| Fragment m/z | `params.min_fr_mz`, `params.max_fr_mz` | |
| Enzyme | `params.cut` | e.g., "K*,R*" |
| Missed cleavages | `params.missed_cleavages` | |
| Met excision | `params.met_excision` | |
| Unimod4 | `params.unimod4` | |

### Hash Generation

```groovy
def cache_key = [
    fasta.md5(),
    params.diann_version,
    params.min_pep_len,
    params.max_pep_len,
    params.min_pr_mz,
    params.max_pr_mz,
    params.min_pr_charge,
    params.max_pr_charge,
    params.min_fr_mz,
    params.max_fr_mz,
    params.cut,
    params.missed_cleavages,
    params.met_excision,
    params.unimod4
].join('|').md5()[0..7]  // Short hash (8 chars)
```

## Implementation

### Module Changes (`modules/library.nf`)

```groovy
process GENERATE_LIBRARY {
    storeDir { "${params.library_cache}/${cache_key}" }

    input:
    path fasta
    val cache_key
    // ... existing inputs

    output:
    path "*.predicted.speclib", emit: library
    path "params.yaml", emit: provenance

    script:
    // ... existing script
    // Add params.yaml generation at end
    """
    # ... existing commands ...

    # Write provenance
    cat > params.yaml << EOF
    generated: \$(date -Iseconds)
    diann_version: ${params.diann_version}
    fasta_md5: ${fasta.md5()}
    # ... all parameters
    EOF
    """
}
```

### Workflow Changes

```groovy
// In create_library.nf
def cache_key = computeCacheKey(fasta_file, params)

GENERATE_LIBRARY(
    fasta_file,
    cache_key,
    // ... other params
)
```

### Profile Configuration

```groovy
// nextflow.config
params {
    library_cache = "${System.getenv('HOME')}/.diann_cache/libraries"
}

profiles {
    slurm {
        params.library_cache = '/home/karlssoc/.diann_cache/libraries'
    }
    cosmos {
        params.library_cache = '/home/karlssoc/.diann_cache/libraries'
    }
}
```

## Cache Management

### Listing Cached Libraries

```bash
# Simple listing
ls -la ~/.diann_cache/libraries/

# With metadata
for d in ~/.diann_cache/libraries/*/; do
    echo "=== $(basename $d) ==="
    cat "$d/params.yaml"
done
```

### Clearing Cache

```bash
# Clear all
rm -rf ~/.diann_cache/libraries/*

# Clear specific entry
rm -rf ~/.diann_cache/libraries/<hash>
```

### Cache Size Monitoring

```bash
du -sh ~/.diann_cache/libraries/
```

## Considerations

### Pros
- Zero execution time for cached libraries
- Automatic via Nextflow's storeDir
- Persists across workflow runs and projects
- Self-documenting via params.yaml

### Cons
- Disk space accumulation (libraries can be 1-5 GB each)
- Manual cache management required
- Hash collisions theoretically possible (8 chars = 4 billion combinations)

### Edge Cases

1. **FASTA file changes but path stays same**: Handled by content-based MD5
2. **DIA-NN update with same version string**: Won't detect - consider including binary checksum
3. **Partial/corrupted cache entries**: storeDir expects all outputs; Nextflow should detect missing files

## InfinDIA Calibration Libraries (Implemented)

DIA-NN 2.3+ includes InfinDIA, a fast pre-search mode that can generate empirical calibration libraries. These libraries speed up RT/IM calibration in subsequent quantification runs.

### Key CLI Flags

| Flag | Purpose |
|------|---------|
| `--pre-search` | Enable InfinDIA pre-search mode |
| `--pre-filter` | Pre-filter candidate precursors |
| `--pre-select N` | Limit to N precursors (faster) |
| `--pre-select-force` | Force the pre-selection limit |
| `--ref <library>` | Use calibration library for RT/IM alignment |

### Mass Accuracy Presets

| Instrument | MS1 | MS2 |
|------------|-----|-----|
| HFX/Orbitrap | 5 ppm | 15 ppm |
| timsTOF | 15 ppm | 15 ppm |

### Implementation

Implemented in `workflows/iterative_quant.nf` with:

```yaml
# Config parameters
calibration_mode: 'infindia'  # or 'existing' or 'none'
calibration_files: 5          # Number of MS files for calibration
instrument_type: 'hfx'        # or 'timstof'
pre_select: 5000              # Limit precursors (0 = unlimited)
```

### Workflow

1. **InfinDIA pre-search** (optional): Generate calibration library from subset of MS files
2. **Library generation**: Generate predicted library from FASTA
3. **Identification**: Quantify with `--ref calibration_lib.parquet`
4. **Library subsetting**: Reduce to identified proteins
5. **Final quantification**: Quantify with `--ref calibration_lib.parquet`

### Notes

- Use 1-5 MS files for calibration (more causes QuantUMS cross-run issues with few samples)
- Calibration library contains empirical RT/IM values from actual data
- Warnings about RT/IM mismatch with predicted libraries are expected
- Calibration is optional but recommended for large predicted libraries

### Module

See `modules/infindia_presearch.nf` for the implementation.

---

## Future Enhancements

### Remote Sync (Deferred)

Options considered but deferred for complexity:
- NAISS storage allocation on COSMOS
- rsync between systems
- Git LFS / DVC for versioned libraries
- Cloud storage mount (s3fs, rclone)

### Cache Expiration

Could add TTL-based cleanup:
```bash
# Delete entries older than 90 days
find ~/.diann_cache/libraries -type d -mtime +90 -exec rm -rf {} \;
```

### Named Presets

Similar to `models/` pattern - manually curated libraries with human-readable names:
```
libraries/
  human-uniprot-2024-01/
    library.predicted.speclib
    metadata.yaml
```

---

*Status: Design draft (InfinDIA calibration implemented)*
*Created: 2025-01-30*
*Updated: 2025-01-31*
