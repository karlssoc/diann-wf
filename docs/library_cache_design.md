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
| Peptide length | `params.library.min_pep_len`, `max_pep_len` | |
| Precursor m/z | `params.library.min_pr_mz`, `max_pr_mz` | |
| Precursor charge | `params.library.min_pr_charge`, `max_pr_charge` | |
| Fragment m/z | `params.library.min_fr_mz`, `max_fr_mz` | |
| Enzyme | `params.library.cut` | e.g., "K*,R*" |
| Missed cleavages | `params.library.missed_cleavages` | |
| Met excision | `params.library.met_excision` | |
| Unimod4 | `params.library.unimod4` | |
| **Model preset** | `params.model_preset` | Pre-trained RT/IM/FR models |

### Pre-trained Models

Pre-trained models (RT, IM, FR) affect library predictions and must be included in the cache key.

**Options:**

| Approach | Pros | Cons |
|----------|------|------|
| Preset name | Fast, simple | Won't detect if preset files change |
| File MD5 | Detects any model change | Slower (~9MB to hash), more complex |

**Recommendation:** Use preset name. If you update a preset's models, rename the preset (e.g., `ttht-evos-30spd-v2`). This is consistent with how presets are versioned in `models/`.

```groovy
// Model identification for cache key
def model_id = params.model_preset ?: 'default'

// Alternative: explicit file checksums (slower, more precise)
// def model_id = [
//     tokens_file.name != 'NO_FILE' ? tokens_file.md5() : 'default',
//     rt_model_file.name != 'NO_FILE' ? rt_model_file.md5() : 'default',
//     im_model_file.name != 'NO_FILE' ? im_model_file.md5() : 'default',
//     fr_model_file.name != 'NO_FILE' ? fr_model_file.md5() : 'default',
// ].join(':')
```

### Hash Generation

```groovy
def cache_key = [
    fasta.md5(),
    params.diann_version,
    params.model_preset ?: 'default',  // Pre-trained models
    params.library?.min_pep_len ?: 7,
    params.library?.max_pep_len ?: 30,
    params.library?.min_pr_mz ?: 350,
    params.library?.max_pr_mz ?: 1650,
    params.library?.min_pr_charge ?: 2,
    params.library?.max_pr_charge ?: 3,
    params.library?.min_fr_mz ?: 200,
    params.library?.max_fr_mz ?: 1800,
    params.library?.cut ?: 'K*,R*',
    params.library?.missed_cleavages ?: 1,
    params.library?.met_excision ?: true,
    params.library?.unimod4 ?: true
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
4. **Model preset files change but name stays same**: Won't detect - rename preset when updating models (e.g., `preset-v2`)
5. **Explicit model paths vs preset**: If using explicit `--rt_model` etc. instead of `--model_preset`, need to hash file contents or use consistent naming

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
*Updated: 2025-01-31 - Added model preset to cache key design*
