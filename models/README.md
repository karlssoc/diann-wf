# Pre-Trained DIA-NN Models

This directory contains pre-trained spectral library models for common instrument/LC/method combinations. Using these models can improve library quality and reduce the need for extensive tuning on your own data.

## Available Presets

Currently, this is a template repository. You can add your own pre-trained models using the collection script (see [Contributing New Models](#contributing-new-models) below).

| Preset Name | Instrument | LC System | Method | Validated |
|-------------|------------|-----------|--------|-----------|
| `example-preset` | Template | Template | Template | ✗ |

See individual `metadata.yaml` files in each preset directory for detailed provenance information.

## Usage

### Option 1: Use Model Preset (Recommended)

Specify a preset name with the `model_preset` parameter:

```bash
nextflow run workflows/create_library.nf \
  --fasta protein.fasta \
  --library_name mylib \
  --model_preset ttht-evos-30spd \
  -profile slurm
```

### Option 2: Use Individual Files

Reference individual model files directly:

```bash
nextflow run workflows/create_library.nf \
  --fasta protein.fasta \
  --library_name mylib \
  --tokens models/ttht-evos-30spd/dict.txt \
  --rt_model models/ttht-evos-30spd/tuned_rt.pt \
  --im_model models/ttht-evos-30spd/tuned_im.pt \
  --fr_model models/ttht-evos-30spd/tuned_fr.pt \
  -profile slurm
```

## Tuning Modes

Control how pre-trained models are used with the `tuning_mode` parameter:

### Skip Tuning (Use Preset Directly)

**Fastest option** - use pre-trained models as-is without additional tuning:

```yaml
# In your config YAML
model_preset: 'ttht-evos-30spd'
tuning_mode: 'skip'
```

**When to use:**
- Your instrument/LC/method matches a preset exactly
- You trust the pre-trained models for your application
- Speed is more important than maximum customization

### Train from Scratch (Default)

**Default behavior** - ignore presets and train from DIA-NN default models:

```yaml
# In your config YAML
tuning_mode: 'from_scratch'  # This is the default
```

**When to use:**
- No preset matches your instrument/method
- You want maximum customization for your specific data
- This is the traditional workflow behavior

### Fine-Tune from Preset (Future)

**Not yet implemented** - use preset as starting point, then fine-tune with your data.

This mode requires verification that DIA-NN CLI supports passing initial models to `--tune-lib`. Check back in future releases.

## Model File Format

Each preset directory contains:

- **`dict.txt`** - Token dictionary (required)
- **`tuned_rt.pt`** - Retention time model (optional)
- **`tuned_im.pt`** - Ion mobility model (optional)
- **`tuned_fr.pt`** - Fragmentation model (optional, requires DIA-NN 2.3.1+)
- **`tune.log`** - Tuning log file with training details (optional, recommended)
- **`metadata.yaml`** - Provenance tracking (required)

## Contributing New Models

Have models from a new instrument/method combination? Add them to the repository!

### Step 1: Collect Models

Use the collection script to gather models from DIA-NN tuning output:

```bash
./bin/collect_models.sh -s /path/to/tuning/output -n my-instrument-method
```

Example:
```bash
# Collect models from a tuning run
./bin/collect_models.sh \
  -s results/ttht_tuning/tuning \
  -n ttht-evos-30spd
```

The script will:
1. Search for model files (dict.txt, tuned_*.pt) in the source directory
2. Copy them to `models/my-instrument-method/`
3. Create a metadata.yaml template

### Step 2: Fill in Metadata

Edit the generated metadata file with provenance information:

```bash
nano models/my-instrument-method/metadata.yaml
```

**Important fields:**
- `instrument`: Full instrument name (e.g., "Bruker timsTOF HT")
- `lc_system`: LC system used (e.g., "Evosep One")
- `method`: Method details (e.g., "30 SPD (samples per day)")
- `diann_version_trained`: DIA-NN version used for training
- `training_library`: Protein database used
- `training_samples`: Number of samples used for training
- `notes`: Training conditions, recommendations, expected performance

### Step 3: Test

Test your new preset with a small library generation run:

```bash
nextflow run workflows/create_library.nf \
  --fasta test.fasta \
  --library_name test_lib \
  --model_preset my-instrument-method \
  -profile standard
```

Check the log output to verify models are being used:
```
Using tuned tokens file
Using tuned RT model
Using tuned IM model
```

### Step 4: Validate

Validate with real samples to ensure models improve results:

1. Generate library with preset models
2. Generate library without preset (default models)
3. Quantify same sample with both libraries
4. Compare results (protein/peptide IDs, library size, RT predictions)

If models improve results, update metadata:
```yaml
validated: true
validation_notes: "Tested on 5 independent samples, 15% improvement in identifications"
```

### Step 5: Commit

Add your models to the repository:

```bash
git add models/my-instrument-method
git commit -m "Add pre-trained models for [instrument]-[LC]-[method]"
```

## Compatibility

### DIA-NN Version

Models should be used with the same DIA-NN version they were trained on for best results. Check `diann_version_trained` in metadata.yaml.

**Version mismatch:** Models will still work across minor versions (e.g., 2.3.0 → 2.3.1), but performance may vary.

### Library Parameters

For best results, use the same library generation parameters as training. Check metadata.yaml for recommended settings.

**Critical parameters to match:**
- Fragment m/z range (`min_fr_mz`, `max_fr_mz`)
- Peptide length range (`min_pep_len`, `max_pep_len`)
- Precursor m/z range (`min_pr_mz`, `max_pr_mz`)
- Charge range (`min_pr_charge`, `max_pr_charge`)
- Enzyme settings (`cut`, `missed_cleavages`)

### Instrument Match

**Best results:** Your instrument/method matches the preset training conditions

**Acceptable:** Similar instrument with same data acquisition mode (e.g., different timsTOF models)

**Not recommended:** Different instrument vendors or acquisition modes (DDA vs. DIA)

## Size Considerations

**Current total:** ~0 MB (template only)

**Projected total:** ~90 MB for 10 instrument presets (~9 MB each)

**Storage strategy:**
- Direct commit to Git (current approach, <100 MB)
- Will migrate to Git LFS if total size exceeds 100 MB

## Troubleshooting

### Preset not found

```
WARN: Model preset 'ttht-evos-30spd' not found at /path/to/models/ttht-evos-30spd
```

**Solution:** Check preset name spelling. List available presets:
```bash
ls models/
```

### Models not being used

Check workflow log for "Using tuned" messages. If missing:

1. Verify model files exist:
   ```bash
   ls -lh models/your-preset/
   ```

2. Verify files are not empty:
   ```bash
   du -h models/your-preset/*
   ```

3. Check parameter priority (explicit paths override presets)

### Version compatibility warning

If you see warnings about DIA-NN version mismatch, either:
- Use the DIA-NN version specified in metadata.yaml
- Retrain models with your current DIA-NN version

### Poor results with preset

Presets work best when your setup matches training conditions. If results are worse:

1. Check instrument/method compatibility in metadata.yaml
2. Verify library parameters match training settings
3. Consider using `tuning_mode: from_scratch` for your specific data

## Further Reading

- **Collection script:** [bin/collect_models.sh](../bin/collect_models.sh)
- **Workflow examples:** [configs/library/](../configs/library/)
- **DIA-NN documentation:** https://github.com/vdemichev/DiaNN
- **Project README:** [README.md](../README.md)

## Questions or Issues?

- Check existing presets for examples
- See [CLAUDE.md](../CLAUDE.md) for implementation details
- Report issues: https://github.com/karlssoc/diann-wf/issues
