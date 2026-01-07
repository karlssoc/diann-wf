#!/bin/bash
# Setup Git LFS for test data files
# Run this once before committing test data

set -e

echo "Setting up Git LFS for test data..."

# Check if Git LFS is installed
if ! command -v git-lfs &> /dev/null; then
    echo "ERROR: Git LFS is not installed"
    echo ""
    echo "Install instructions:"
    echo "  macOS:   brew install git-lfs"
    echo "  Ubuntu:  sudo apt install git-lfs"
    echo "  Other:   https://git-lfs.github.com/"
    exit 1
fi

# Initialize Git LFS for this repository
echo "Initializing Git LFS..."
git lfs install

# Track .dia files and other large files in test_data
echo "Configuring LFS tracking for test data..."
git lfs track "test_data/**/*.dia"
git lfs track "test_data/**/*.mzML"
git lfs track "test_data/**/*.mzML.gz"

# Also track expected outputs if they're large
git lfs track "test_data/expected_outputs/*.speclib"
git lfs track "test_data/expected_outputs/*.parquet"

# Show what's being tracked
echo ""
echo "Git LFS is now tracking:"
cat .gitattributes | grep "test_data"

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Generate test data: cd generate_example_data && ./create_test_data.sh"
echo "  2. Add files: git add .gitattributes test_data/"
echo "  3. Commit: git commit -m 'Add test data with Git LFS (28 MB)'"
echo "  4. Push: git push"
echo ""
echo "Note: First push will upload ~28 MB to Git LFS storage"
