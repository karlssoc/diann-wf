#!/bin/bash
# Setup verification script for DIANN Nextflow workflows

set -e

echo "=================================="
echo "DIANN Workflow Setup Verification"
echo "=================================="
echo ""

# Check Nextflow
echo "Checking Nextflow..."
if command -v nextflow &> /dev/null; then
    NF_VERSION=$(nextflow -version | head -n1)
    echo "✓ Nextflow found: $NF_VERSION"
else
    echo "✗ Nextflow not found. Install from: https://www.nextflow.io"
    exit 1
fi
echo ""

# Check Singularity
echo "Checking Singularity/Apptainer..."
if command -v singularity &> /dev/null; then
    SING_VERSION=$(singularity --version)
    echo "✓ Singularity found: $SING_VERSION"
elif command -v apptainer &> /dev/null; then
    APP_VERSION=$(apptainer --version)
    echo "✓ Apptainer found: $APP_VERSION"
else
    echo "✗ Singularity/Apptainer not found"
    exit 1
fi
echo ""

# Check SLURM
echo "Checking SLURM..."
if command -v sbatch &> /dev/null; then
    echo "✓ SLURM found"
    SLURM_ACCOUNT=$(sacctmgr show associations user=$USER format=account -P -n | head -n1)
    if [ -n "$SLURM_ACCOUNT" ]; then
        echo "  Your SLURM accounts:"
        sacctmgr show associations user=$USER format=account,qos -P | grep -v "Account|^$" | sort -u
    fi
else
    echo "⚠ SLURM not found (you can still run locally)"
fi
echo ""

# Check container access
echo "Checking container registry access..."
if singularity remote list &> /dev/null; then
    echo "✓ Singularity remote configured"
else
    echo "⚠ Singularity remote not configured (may be fine)"
fi
echo ""

# Test container pull (optional)
echo "Testing container pull (this may take a moment)..."
CONTAINER_URL="docker://quay.io/karlssoc/diann:2.3.1"
TEST_CONTAINER="/tmp/diann_test_$$.sif"

if timeout 30s singularity pull --name "$TEST_CONTAINER" "$CONTAINER_URL" &> /dev/null; then
    echo "✓ Successfully pulled test container from quay.io/karlssoc/diann"
    rm -f "$TEST_CONTAINER"
else
    echo "⚠ Could not pull container (may require authentication or VPN)"
    echo "  Try manually: singularity pull docker://quay.io/karlssoc/diann:2.3.1"
fi
echo ""

# Check project structure
echo "Checking project structure..."
REQUIRED_DIRS=("workflows" "modules" "configs")
REQUIRED_FILES=("nextflow.config" "README.md")

for dir in "${REQUIRED_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "✓ Directory exists: $dir/"
    else
        echo "✗ Missing directory: $dir/"
    fi
done

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "✓ File exists: $file"
    else
        echo "✗ Missing file: $file"
    fi
done
echo ""

# Summary
echo "=================================="
echo "Setup Summary"
echo "=================================="
echo ""
echo "If all checks passed, you're ready to run:"
echo ""
echo "  # Simple quantification"
echo "  nextflow run workflows/quantify_only.nf -params-file configs/simple_quant.yaml -profile slurm"
echo ""
echo "  # Create library"
echo "  nextflow run workflows/create_library.nf -params-file configs/library_creation.yaml -profile slurm"
echo ""
echo "  # Full pipeline"
echo "  nextflow run workflows/full_pipeline.nf -params-file configs/full_pipeline.yaml -profile slurm"
echo ""
echo "See QUICKSTART.md for detailed instructions."
echo ""
