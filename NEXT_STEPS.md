# 🚀 Next Steps: Push to GitHub and Deploy

Your DIANN Nextflow workflow is ready! Here's what to do next.

## ✅ What's Been Created

```
diann-wf/
├── 📄 Documentation
│   ├── README.md              # Complete documentation
│   ├── QUICKSTART.md          # 5-minute tutorial
│   ├── PROJECT_SUMMARY.md     # Design overview
│   ├── GITHUB_SETUP.md        # ⭐ Push to GitHub instructions
│   └── DEPLOY.md              # Server deployment guide
│
├── ⚙️ Workflows
│   ├── workflows/quantify_only.nf      # Simple quantification (most common)
│   ├── workflows/create_library.nf     # Library creation
│   └── workflows/full_pipeline.nf      # Multi-round pipeline
│
├── 🧩 Modules (reusable)
│   ├── modules/quantify.nf
│   ├── modules/library.nf
│   └── modules/tune.nf
│
├── 📝 Example Configs
│   ├── configs/simple_quant.yaml       # For testing
│   ├── configs/library_creation.yaml
│   └── configs/full_pipeline.yaml
│
├── 🖥️ Server Examples
│   ├── server-examples/simple_quantification.yaml.example
│   ├── server-examples/full_pipeline.yaml.example
│   └── server-examples/ttht_replication.yaml.example
│
└── 🔧 Configuration
    ├── nextflow.config         # Base config (SLURM, containers)
    ├── .gitignore             # Git ignore rules
    ├── LICENSE                # MIT license
    └── bin/check_setup.sh     # Setup verification script

✅ Git repository initialized
✅ Initial commit created
✅ Ready to push to GitHub
```

## 📍 You Are Here

```
[✅ Created]  →  [📤 Push to GitHub]  →  [🖥️ Use on Server]
```

## Step 1: Push to GitHub (5 minutes)

Follow the detailed instructions in **[GITHUB_SETUP.md](GITHUB_SETUP.md)** or use this quick version:

### Quick Version

```bash
# 1. Create repository on GitHub
#    Go to: https://github.com/new
#    Name: diann-wf
#    Visibility: Public or Private
#    DON'T initialize with README

# 2. Add remote and push
cd /Users/karlssoc/Projects/Admin/get-organized/diann-wf

git remote add origin git@github.com:karlssoc/diann-wf.git
# Or if using HTTPS: git remote add origin https://github.com/karlssoc/diann-wf.git

git push -u origin main

# 3. (Optional) Create release tag
git tag -a v1.0.0 -m "Release v1.0.0: Initial stable release"
git push origin v1.0.0

# 4. Verify it worked
nextflow info karlssoc/diann-wf
```

## Step 2: Test on Remote Server (10 minutes)

Once on GitHub, test from your server:

```bash
# SSH to your server
ssh kraken

# Create test project
mkdir -p /srv/data1/karlssoc/projects/test_nextflow
cd /srv/data1/karlssoc/projects/test_nextflow

# Test that workflow is accessible
nextflow pull karlssoc/diann-wf
nextflow info karlssoc/diann-wf

# You should see:
# project name: karlssoc/diann-wf
# repository  : https://github.com/karlssoc/diann-wf
# ...
```

## Step 3: Run Your First Workflow

### Option A: Quick Test with Existing tt/lfqb Data

```bash
# On kraken server
cd /srv/data1/karlssoc/projects/tt/lfqb/

# Create config directory
mkdir -p configs

# Copy example config
cat > configs/test_quantification.yaml << 'EOF'
library: '/srv/data1/karlssoc/projects/tt/lfqb/idmapping_2025_11_20.predicted.speclib'
fasta: '/srv/data1/karlssoc/projects/tt/lfqb/idmapping_2025_11_20.fasta'

samples:
  - id: 'p2'
    dir: '/srv/data1/karlssoc/projects/tt/lfqb/input/p2'
    file_type: 'd'

threads: 60
outdir: '/srv/data1/karlssoc/projects/tt/lfqb/results/nextflow_test'
slurm_account: 'my_username'  # CHANGE THIS!

pg_level: 1
mass_acc_cal: 25
smart_profiling: true
individual_mass_acc: true
matrices: true
EOF

# Edit with your SLURM account
nano configs/test_quantification.yaml

# Run simple quantification
nextflow run karlssoc/diann-wf \
  -params-file configs/test_quantification.yaml \
  -profile slurm
```

### Option B: Full Multi-Round Pipeline

```bash
# Use the ttht_replication example
cd /srv/data1/karlssoc/projects/tt/lfqb/
mkdir -p configs

# Download the example from GitHub or create it:
cat > configs/full_pipeline.yaml << 'EOF'
fasta: '/srv/data1/karlssoc/projects/tt/lfqb/idmapping_2025_11_20.fasta'

samples:
  - {id: 'mann', dir: '/srv/data1/karlssoc/projects/tt/lfqb/input/mann', file_type: 'd'}
  - {id: 'p2', dir: '/srv/data1/karlssoc/projects/tt/lfqb/input/p2', file_type: 'd'}
  - {id: 'std', dir: '/srv/data1/karlssoc/projects/tt/lfqb/input/std', file_type: 'd'}

tune_sample: 'p2'
run_r1: true
run_tune: true
run_r2: true
run_r3: true

r1_diann_version: '2.3.1'
r2_diann_version: '2.2.0'
r3_diann_version: '2.3.1'

threads: 60
outdir: '/srv/data1/karlssoc/projects/tt/lfqb/results/full_pipeline'
slurm_account: 'my_username'  # CHANGE THIS!

tuning:
  tune_rt: true
  tune_im: true
  tune_fr: true

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

pg_level: 1
mass_acc_cal: 25
smart_profiling: true
individual_mass_acc: true
matrices: true
EOF

# Edit SLURM account
nano configs/full_pipeline.yaml

# Run complete pipeline
nextflow run karlssoc/diann-wf/workflows/full_pipeline.nf \
  -params-file configs/full_pipeline.yaml \
  -profile slurm
```

## Step 4: Monitor and Check Results

```bash
# Monitor SLURM jobs
squeue -u $USER
watch squeue -u $USER

# Check Nextflow log
tail -f .nextflow.log

# View results
ls -lh results/
ls -lh results/pipeline_info/  # Execution reports
```

## Common Commands Reference

```bash
# Pull latest workflow version
nextflow pull karlssoc/diann-wf

# Force update
nextflow pull karlssoc/diann-wf -f

# Check workflow info
nextflow info karlssoc/diann-wf

# Resume failed run
nextflow run karlssoc/diann-wf \
  -params-file my_config.yaml \
  -profile slurm \
  -resume

# Use specific version
nextflow run karlssoc/diann-wf \
  -r v1.0.0 \
  -params-file my_config.yaml \
  -profile slurm

# Override parameters on command line
nextflow run karlssoc/diann-wf \
  -params-file my_config.yaml \
  --threads 40 \
  --diann_version 2.2.0 \
  -profile slurm
```

## 📚 Documentation Guide

| Document | When to Use |
|----------|-------------|
| **[GITHUB_SETUP.md](GITHUB_SETUP.md)** | ⭐ Push workflow to GitHub (DO THIS FIRST) |
| **[DEPLOY.md](DEPLOY.md)** | Set up and use on remote server |
| **[QUICKSTART.md](QUICKSTART.md)** | 5-minute tutorial for beginners |
| **[README.md](README.md)** | Complete reference documentation |
| **[PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)** | Design decisions and comparisons |

## 🎯 Quick Reference Card

### Most Common Usage (90% of cases)

```bash
# Create config
cat > my_config.yaml << EOF
library: '/path/to/library.speclib'
fasta: '/path/to/protein.fasta'
samples:
  - {id: 'sample1', dir: '/path/to/input/sample1', file_type: 'd'}
threads: 60
outdir: 'results'
slurm_account: 'my_account'
EOF

# Run
nextflow run karlssoc/diann-wf \
  -params-file my_config.yaml \
  -profile slurm
```

### Three Workflow Types

| Workflow | Command | Use When |
|----------|---------|----------|
| **quantify_only** | `nextflow run karlssoc/diann-wf` | Have existing library, need to quantify |
| **create_library** | `nextflow run karlssoc/diann-wf/workflows/create_library.nf` | Need to create new library from FASTA |
| **full_pipeline** | `nextflow run karlssoc/diann-wf/workflows/full_pipeline.nf` | Need complete R1→Tune→R2→R3 analysis |

## ✅ Success Checklist

- [ ] Pushed to GitHub: `git push -u origin main`
- [ ] Verified GitHub access: `nextflow info karlssoc/diann-wf`
- [ ] Created test config on server
- [ ] Ran first workflow successfully
- [ ] Checked results in output directory
- [ ] Reviewed execution reports in `results/pipeline_info/`

## 🆘 Help & Troubleshooting

### If GitHub Push Fails

See [GITHUB_SETUP.md](GITHUB_SETUP.md) troubleshooting section

### If Nextflow Can't Find Workflow

```bash
# Check GitHub repository is public/accessible
curl https://api.github.com/repos/karlssoc/diann-wf

# Force pull
nextflow pull karlssoc/diann-wf -f
```

### If SLURM Jobs Fail

```bash
# Check SLURM account
sacctmgr show associations user=$USER

# View job details
scontrol show job <job_id>

# Check Nextflow log
less .nextflow.log
```

## 📞 Getting Help

1. **Documentation**: Check the relevant .md file above
2. **Nextflow docs**: https://www.nextflow.io/docs/latest/
3. **DIANN docs**: https://github.com/vdemichev/DiaNN
4. **Execution logs**: `.nextflow.log` and `results/pipeline_info/`

---

**You're all set!** 🎉

Follow [GITHUB_SETUP.md](GITHUB_SETUP.md) to push to GitHub, then start using with:

```bash
nextflow run karlssoc/diann-wf -params-file my_config.yaml -profile slurm
```

Good luck with your mass spectrometry analysis!
