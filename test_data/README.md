# Test Data

Minimal test data for automated testing and validation of the DIA-NN Nextflow workflow.

## Directory Structure

```
test_data/
├── README.md                           # This file
├── setup_git_lfs.sh                    # Git LFS setup script
├── fasta/
│   └── minimal_proteome.fasta          # Small FASTA (100-500 proteins, ~100-200 KB)
├── raw/
│   ├── sample1/
│   │   └── test_sample1.mzML           # Test MS file (~14 MB)
│   └── sample2/
│       └── test_sample2.mzML           # Test MS file (~14 MB)
└── expected_outputs/
    └── test_library.predicted.speclib  # Pre-generated library (optional)
```

## Size Summary

- **2 mzML files:** ~14 MB each = **28 MB total**
- **1 FASTA file:** ~100-200 KB
- **Total:** ~28-30 MB (managed with Git LFS)

## Why 2 Samples?

The refactored workflows specifically test multi-sample functionality:
- ✅ Channel broadcasting (prevents consumption bugs)
- ✅ Parallel sample processing
- ✅ Dynamic resource allocation per sample
- ✅ Real-world workflow patterns

**One sample is insufficient** to test these critical features.

## Setup Instructions

### 1. Generate Test Data

```bash
cd ../generate_example_data
./create_test_data.sh
```

This creates 2 test mzML files (~14 MB each) from the full dataset.

### 2. Add Minimal FASTA

You need to provide a minimal FASTA file:

```bash
# Option A: Extract from your existing FASTA
head -n 1200 your_proteome.fasta > test_data/fasta/minimal_proteome.fasta

# Option B: Download a small proteome (e.g., E. coli)
# Then subset to first 200-500 proteins
```

**Target size:** 100-500 proteins (~50-200 KB)

### 3. Setup Git LFS (Recommended)

For 28 MB of test data, use Git LFS:

```bash
cd test_data
./setup_git_lfs.sh
```

This configures Git LFS to handle the mzML files efficiently.

### 4. Generate Test Library (Optional)

Pre-generate a library for faster testing:

```bash
nextflow run workflows/create_library.nf \
  -params-file configs/test/library_test.yaml \
  -profile standard
```

This creates `test_data/expected_outputs/test_library.predicted.speclib`.

## Running Tests

### Quick Validation Test

```bash
# Test quantification workflow (uses 2 samples)
nextflow run workflows/quantify_only.nf \
  -params-file configs/test/quick_test.yaml \
  -profile standard
```

**Expected runtime:** 5-10 minutes total

### Test Library Generation

```bash
nextflow run workflows/create_library.nf \
  -params-file configs/test/library_test.yaml \
  -profile standard
```

**Expected runtime:** 30-60 seconds

### Test Multi-Sample Workflows

```bash
# Compare libraries workflow (4 quantification jobs)
nextflow run workflows/compare_libraries.nf \
  -params-file configs/test/compare_test.yaml \
  -profile standard
```

## What Gets Tested

With 2 samples, you validate:

1. **Sample parsing** - YAML/JSON/List handling
2. **File counting** - Dynamic time allocation
3. **Channel creation** - Broadcasting to multiple samples
4. **Multi-sample quantification** - Parallel/sequential processing
5. **Model resolution** - Preset and explicit paths
6. **Output organization** - Subdirectory structure

## File Specifications

### mzML Files
- **Format:** Centroid mzML (Thermo data)
- **MS Levels:** MS1 + MSn (DIA windows)
- **Spectra count:** ~1500-2000 per file
- **RT range:** ~10 minutes
- **Size:** ~14 MB uncompressed

### FASTA File
- **Proteins:** 100-500
- **Format:** Standard FASTA
- **Size:** ~100-200 KB
- **Organism:** Any (preferably matches MS data)

## Git LFS Details

After running `setup_git_lfs.sh`, Git LFS will track:
- `test_data/**/*.mzML`
- `test_data/**/*.mzML.gz`
- `test_data/expected_outputs/*.speclib`
- `test_data/expected_outputs/*.parquet`

**Storage usage:**
- First clone: Downloads ~28 MB from LFS
- Subsequent clones: Same (~28 MB)
- Repo size without LFS data: <100 KB

## CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Nextflow Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          lfs: true  # Important: Download LFS files
      - uses: nf-core/setup-nextflow@v1
      - name: Run quick test
        run: |
          nextflow run workflows/quantify_only.nf \
            -params-file configs/test/quick_test.yaml \
            -profile standard
```

## Maintenance

### Updating Test Data

If you need to regenerate test data:

1. Update source files in `generate_example_data/`
2. Run `create_test_data.sh`
3. Test locally
4. Commit with Git LFS

### Validating Test Data

Check that test files are valid:

```bash
# Check mzML files are readable
head -100 test_data/raw/sample1/test_sample1.mzML

# Check FASTA format
grep "^>" test_data/fasta/minimal_proteome.fasta | head -10

# Run test workflow
nextflow run workflows/quantify_only.nf \
  -params-file configs/test/quick_test.yaml \
  -profile standard
```

## Size Constraints

**Keep test data minimal:**
- ✅ 28 MB total (with LFS) - Acceptable
- ⚠️ 50+ MB total - Consider reducing
- ❌ 100+ MB total - Too large, reduce RT range

If test files exceed 30 MB total, reduce the time range:
```bash
# Reduce from 10 minutes to 5 minutes
--filter "scanTime [0,5]"  # ~7 MB per file
```

## Troubleshooting

**Test fails with "file not found":**
- Ensure test data was generated: `ls test_data/raw/*/test_sample*.mzML`
- Check FASTA exists: `ls test_data/fasta/*.fasta`

**Git LFS files not downloading:**
```bash
git lfs pull
```

**Files too large for git:**
- Use Git LFS: `./setup_git_lfs.sh`
- Or reduce file size in `create_test_data.sh`

## Notes

- Test data files are **NOT** production quality
- Designed for workflow validation, not scientific results
- Keep file sizes minimal for fast CI/CD
- 2 samples minimum for comprehensive testing
- Protect original data - never commit full 400 MB files!

---

*Generated from: CK_M2512_002/003.mzML (first 10 minutes)*
*Total size: ~28 MB (2 samples × 14 MB)*
*Managed with Git LFS*
