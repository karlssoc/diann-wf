# GitHub Setup Instructions

Follow these steps to push the workflow to GitHub and start using it from your server.

## Step 1: Create GitHub Repository

### Option A: Via GitHub Web Interface (Recommended)

1. Go to https://github.com/new
2. Repository name: `diann-wf`
3. Description: `Modular Nextflow workflows for DIA-NN mass spectrometry analysis`
4. Choose **Public** or **Private** (your choice)
5. **DO NOT** initialize with README, .gitignore, or license (we already have these)
6. Click "Create repository"

### Option B: Via GitHub CLI

```bash
gh repo create diann-wf --public --description "Modular Nextflow workflows for DIA-NN mass spectrometry analysis"
```

## Step 2: Push to GitHub

```bash
# Ensure you're in the diann-wf directory
cd /Users/karlssoc/Projects/Admin/get-organized/diann-wf

# Set default branch to main
git branch -M main

# Add all files
git add .

# Create first commit
git commit -m "Initial commit: Modular DIANN Nextflow workflows

- Three flexible workflows: quantify_only, create_library, full_pipeline
- Reusable modules for quantification, library generation, and tuning
- SLURM integration with automatic resource allocation
- Support for DIANN versions 2.3.1, 2.2.0, 1.8.1
- Comprehensive documentation and examples
"

# Add remote (replace 'karlssoc' with your GitHub username if different)
git remote add origin git@github.com:karlssoc/diann-wf.git

# Or if using HTTPS:
# git remote add origin https://github.com/karlssoc/diann-wf.git

# Push to GitHub
git push -u origin main
```

## Step 3: Create First Release (Optional but Recommended)

Creating releases makes it easy to pin specific versions:

```bash
# Tag the first version
git tag -a v1.0.0 -m "Release v1.0.0: Initial stable release

Features:
- Simple quantification workflow
- Library creation workflow
- Full multi-round pipeline
- Automatic .d file parameter handling
- SLURM integration
- Container support for DIANN 2.3.1, 2.2.0, 1.8.1
"

# Push the tag
git push origin v1.0.0
```

Or create a release via GitHub web interface:
1. Go to your repository on GitHub
2. Click "Releases" → "Create a new release"
3. Tag version: `v1.0.0`
4. Release title: `v1.0.0 - Initial Release`
5. Add description
6. Click "Publish release"

## Step 4: Verify GitHub Setup

Check that your repository is accessible:

```bash
# View repository info
nextflow info karlssoc/diann-wf

# Or visit in browser
# https://github.com/karlssoc/diann-wf
```

## Step 5: Test from Remote Server

SSH to your server and test:

```bash
# SSH to server
ssh kraken

# Create a test project
mkdir -p ~/test_diann_workflow
cd ~/test_diann_workflow

# Create a minimal test config
cat > test_config.yaml << 'EOF'
library: '/path/to/test/library.speclib'
fasta: '/path/to/test.fasta'
samples:
  - {id: 'test', dir: '/path/to/test/input', file_type: 'd'}
threads: 2
outdir: 'test_results'
slurm_account: 'my_account'
EOF

# Test that workflow can be fetched (dry-run)
nextflow pull karlssoc/diann-wf

# Check it was downloaded
nextflow info karlssoc/diann-wf
```

## Step 6: Update README Badges (Optional)

Add status badges to your README.md:

```markdown
# DIANN Nextflow Workflows

[![Nextflow](https://img.shields.io/badge/nextflow-%E2%89%A521.04.0-brightgreen.svg)](https://www.nextflow.io/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/v/release/karlssoc/diann-wf)](https://github.com/karlssoc/diann-wf/releases)
```

## Using the Workflow from GitHub

Once pushed, anyone (or just you) can use it:

### Basic Usage

```bash
# Latest version
nextflow run karlssoc/diann-wf \
  -params-file my_config.yaml \
  -profile slurm

# Specific version (recommended for reproducibility)
nextflow run karlssoc/diann-wf \
  -r v1.0.0 \
  -params-file my_config.yaml \
  -profile slurm

# Specific workflow
nextflow run karlssoc/diann-wf/workflows/quantify_only.nf \
  -params-file my_config.yaml \
  -profile slurm
```

### Update Workflow

```bash
# Pull latest changes
nextflow pull karlssoc/diann-wf

# Force update
nextflow pull karlssoc/diann-wf -f
```

## Making Changes

When you update the workflow:

```bash
# Make your changes locally
cd /Users/karlssoc/Projects/Admin/get-organized/diann-wf

# Edit files...
nano modules/quantify.nf

# Commit changes
git add .
git commit -m "Update: improved quantification parameters"
git push

# Create new release (optional)
git tag -a v1.1.0 -m "Release v1.1.0: Improved quantification"
git push origin v1.1.0
```

Users can then update:

```bash
# On server
nextflow pull karlssoc/diann-wf

# Or use new version
nextflow run karlssoc/diann-wf -r v1.1.0 ...
```

## Private Repository Setup

If you made the repository private:

1. **Ensure SSH keys are set up** on your server:
   ```bash
   # Generate SSH key if you don't have one
   ssh-keygen -t ed25519 -C "your_email@example.com"

   # Add to GitHub: Settings → SSH and GPG keys → New SSH key
   cat ~/.ssh/id_ed25519.pub
   ```

2. **Or use Personal Access Token** for HTTPS:
   ```bash
   # Create token: GitHub → Settings → Developer settings → Personal access tokens
   # Then use:
   nextflow run https://YOUR_TOKEN@github.com/karlssoc/diann-wf ...
   ```

## Sharing with Collaborators

If working with others:

1. **Add collaborators**: Repository → Settings → Collaborators
2. **They can then use**:
   ```bash
   nextflow run karlssoc/diann-wf -params-file their_config.yaml -profile slurm
   ```
3. **Pin versions in publications**:
   ```bash
   # In methods: "Analysis performed using diann-wf v1.0.0"
   nextflow run karlssoc/diann-wf -r v1.0.0 ...
   ```

## Troubleshooting

### Issue: "Repository not found"

**Solution:** Check repository name and permissions:
```bash
# Verify repository exists
curl https://api.github.com/repos/karlssoc/diann-wf

# Check your GitHub authentication
ssh -T git@github.com
```

### Issue: "Permission denied"

**Solution:** Check SSH keys or use HTTPS with token

### Issue: "Cannot pull updates"

**Solution:** Force update:
```bash
nextflow pull karlssoc/diann-wf -f
```

## Success Checklist

- [ ] Repository created on GitHub
- [ ] Code pushed to GitHub
- [ ] README.md displays correctly on GitHub
- [ ] Release v1.0.0 created (optional)
- [ ] `nextflow info karlssoc/diann-wf` works
- [ ] Tested pull from remote server
- [ ] Server configs created in project directories

## Next Steps

1. See [DEPLOY.md](DEPLOY.md) for server deployment instructions
2. See [QUICKSTART.md](QUICKSTART.md) for usage tutorial
3. See [README.md](README.md) for complete documentation

You're now ready to use `nextflow run karlssoc/diann-wf` from any server! 🎉
