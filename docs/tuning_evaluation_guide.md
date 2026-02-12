# DIA-NN Model Tuning Evaluation Guide

## Training Set Size Recommendations

### Minimum Viable
- **RT model**: 10,000-20,000 peptides
- **IM model**: 20,000-50,000 peptides (if applicable)
- **FR model**: 50,000-100,000 peptides

### Optimal Range
- **100,000-150,000 precursors** (sweet spot for most instruments)
- Balances diversity, training time, and model performance

### Quality Indicators
```bash
# Your library should show:
grep "Spectral library loaded" tune.log
# Look for:
# - 100K+ precursors (good)
# - 10K+ protein groups (diverse)
# - Converging loss curves (not plateau or diverging)
```

## Sample Splitting Strategy

### Option A: Separate Experiments (Recommended)
```yaml
# configs/workflows/evaluate_tuning.yaml
training:
  samples:
    - {id: 'train1', dir: 'data/training/sample1'}
    - {id: 'train2', dir: 'data/training/sample2'}
    - {id: 'train3', dir: 'data/training/sample3'}

validation:
  samples:
    - {id: 'val1', dir: 'data/validation/sample1'}
    - {id: 'val2', dir: 'data/validation/sample2'}
```

### Option B: Time-Based Split
- Training: First 70% of gradient time
- Validation: Last 30% of gradient time
- Ensures completely independent peptides

### Option C: Random Peptide Split
- Less recommended (similar peptides may appear in both sets)
- Use only if samples are limited

## Evaluation Metrics

### 1. Identification Rate (Primary)

**Protein level:**
```bash
# Extract from report.stats.tsv
awk -F'\t' 'NR==1 {for(i=1;i<=NF;i++) if($i=="Proteins.Identified") col=i}
             NR>1 {print $col}' report.stats.tsv
```

**Expected improvement:**
- **RT tuning alone**: +5-15% proteins
- **IM tuning** (dia-PASEF): +10-20% proteins
- **FR tuning**: +3-8% proteins
- **All combined**: +15-30% proteins

### 2. Quantification Quality

**Technical replicate CV:**
```bash
# From main report (report.tsv)
# Calculate CV for each protein across replicates
# Lower CV = better tuning

# Expected CV improvement:
# Default models: 15-25% median CV
# Tuned models: 10-18% median CV
```

**Missing value rate:**
```bash
# Count missing values in report.tsv
# Tuned models should have fewer missing values
```

### 3. Confidence Scores

**q-value distributions:**
```r
# In R, compare q-value distributions
library(data.table)

default <- fread("output/default/report.tsv")
tuned <- fread("output/tuned/report.tsv")

# Compare median q-values at 1% FDR cutoff
median(default[Q.Value < 0.01]$Q.Value)
median(tuned[Q.Value < 0.01]$Q.Value)

# Tuned should have lower median q-values
```

## Workflow for Evaluation

### Step 1: Split Your Data
```bash
# Create training and validation sample lists
mkdir -p configs/evaluation
```

### Step 2: Generate Library + Tune (Training Set)
```bash
nextflow run workflows/full_pipeline.nf \
  -params-file configs/evaluation/training.yaml \
  -profile slurm
```

### Step 3: Quantify with Both Models (Validation Set)

**3a. Default models:**
```yaml
# configs/evaluation/validation_default.yaml
library: 'path/to/training_output/library.predicted.speclib'
tuning_mode: 'skip'  # Don't use tuned models
model_preset: null
samples:
  - {id: 'val1', dir: 'data/validation/sample1'}
  - {id: 'val2', dir: 'data/validation/sample2'}
outdir: 'results/evaluation/default'
```

```bash
nextflow run karlssoc/diann-wf -entry quantify_only \
  -params-file configs/evaluation/validation_default.yaml \
  -profile slurm
```

**3b. Tuned models:**
```yaml
# configs/evaluation/validation_tuned.yaml
library: 'path/to/training_output/library.predicted.speclib'
model_preset: 'training-run-2026-01-14'  # Your tuned models
samples:
  - {id: 'val1', dir: 'data/validation/sample1'}
  - {id: 'val2', dir: 'data/validation/sample2'}
outdir: 'results/evaluation/tuned'
```

```bash
nextflow run karlssoc/diann-wf -entry quantify_only \
  -params-file configs/evaluation/validation_tuned.yaml \
  -profile slurm
```

### Step 4: Compare Results

**Quick comparison script:**
```bash
#!/bin/bash
# bin/compare_tuning_results.sh

echo "=== Tuning Evaluation Results ==="
echo ""
echo "Training set stats:"
grep "Spectral library loaded" results/training/tune/tune.log

echo ""
echo "Validation - Default Models:"
awk -F'\t' 'NR==2 {print "Proteins: "$0}' \
  results/evaluation/default/val1/report.stats.tsv | \
  grep -o "Proteins.Identified: [0-9]*"

echo ""
echo "Validation - Tuned Models:"
awk -F'\t' 'NR==2 {print "Proteins: "$0}' \
  results/evaluation/tuned/val1/report.stats.tsv | \
  grep -o "Proteins.Identified: [0-9]*"

echo ""
echo "Improvement:"
# Calculate percentage increase
```

## Success Criteria

### Minimal Success (Tuning is Working)
- ✅ **+5% protein identifications** on validation set
- ✅ **Lower median q-values** at 1% FDR
- ✅ **Stable across samples** (not just one outlier)

### Good Success (Worth Using)
- ✅ **+10-15% protein identifications**
- ✅ **-20% median CV** in technical replicates
- ✅ **-10% missing values**

### Excellent Success (Optimal Tuning)
- ✅ **+20%+ protein identifications**
- ✅ **Consistent across different sample types**
- ✅ **Visible q-value distribution shift**

## Common Pitfalls

### ❌ **Circular Evaluation**
```bash
# WRONG: Training and testing on same data
# Generate library from sample1.dia
# Tune models using sample1.dia library
# Quantify sample1.dia with tuned models → Circular!
```

### ❌ **Insufficient Training Data**
```bash
# WRONG: Only 10K precursors
# RT model might work, but FR model needs 50K+
```

### ❌ **Over-filtering Training Data**
```bash
# WRONG: Only use "perfect" PSMs
# Better: Include diverse chemical space, let model learn
```

### ✅ **Correct Approach**
```bash
# RIGHT: Completely separate experiments
# Training: samples 1-3 → generate library → tune models
# Validation: samples 4-5 → quantify with default vs tuned
# Compare identification rates on validation set
```

## Advanced: Cross-Validation

For limited samples, use k-fold cross-validation:

```bash
# Fold 1: Train on samples 1-3, test on 4-5
# Fold 2: Train on samples 2-4, test on 1,5
# Fold 3: Train on samples 3-5, test on 1-2
# Average improvement across folds
```

## Model Persistence

Once validated, save your tuned models:
```bash
./bin/collect_models.sh \
  -s results/training/tune \
  -n my-instrument-$(date +%Y%m%d)
```

Then use in production:
```yaml
model_preset: 'my-instrument-20260114'
tuning_mode: 'skip'  # Use pre-trained models directly
```

## References

- DIA-NN documentation: https://github.com/vdemichev/DiaNN
- Deep learning for proteomics: Demichev et al, Nature Methods, 2020
- Transfer learning in MS: Gessulat et al, Nature Methods, 2019

---

*Generated: 2026-01-14*
