# Server Configuration Examples

These are example configurations meant to be copied to your server and modified with your actual paths.

**⚠️ IMPORTANT:** These configs are **EXAMPLES ONLY**. Do not use these directly - they contain placeholder paths.

## How to Use

1. Copy the relevant example to your server project directory
2. Rename it (remove `.example` suffix)
3. Edit with your actual server paths
4. Run with `nextflow run karlssoc/diann-wf`

## Example Workflow

```bash
# On your server (e.g., kraken)
cd /srv/data1/karlssoc/projects/my_experiment/

# Copy example
cp ~/diann-wf/server-examples/simple_quantification.yaml configs/my_config.yaml

# Edit with your paths
nano configs/my_config.yaml

# Run from GitHub
nextflow run karlssoc/diann-wf \
  -params-file configs/my_config.yaml \
  -profile slurm
```

## Files in This Directory

- `simple_quantification.yaml.example` - Basic quantification with existing library
- `create_library.yaml.example` - Create new spectral library
- `full_pipeline.yaml.example` - Complete multi-round pipeline
- `ttht_replication.yaml.example` - Replicate the tt/lfqb workflow

## Important Notes

1. **Use absolute paths** - All paths must be absolute (start with `/`)
2. **Check file types** - `.d`, `.raw`, or `.mzML`
3. **Verify SLURM account** - Use `sacctmgr show associations user=$USER`
4. **Test first** - Use `-profile test` before submitting to SLURM

## Configuration Templates by Use Case

### Use Case 1: Daily Quantification
→ Use `simple_quantification.yaml.example`

### Use Case 2: New Organism/Library
→ Use `create_library.yaml.example`

### Use Case 3: Publication-Quality Analysis
→ Use `full_pipeline.yaml.example`
