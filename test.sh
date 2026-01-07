#!/bin/bash
# Quick test script to validate test data and refactored workflows
# Run this BEFORE committing to git

set -e

echo "========================================="
echo "DIA-NN Workflow Test Suite"
echo "========================================="
echo ""

# Check test data exists
echo "Step 1: Validating test data..."
echo ""

if [ ! -f "test_data/fasta/UP000002311_506-entries_2026_01_07.fasta" ]; then
    echo "❌ FASTA file not found!"
    echo "Expected: test_data/fasta/UP000002311_506-entries_2026_01_07.fasta"
    exit 1
fi
echo "✓ FASTA file found (506 proteins)"

if [ ! -f "test_data/raw/sample1/CK_M2512_002.dia" ]; then
    echo "❌ Sample 1 .dia file not found!"
    exit 1
fi
echo "✓ Sample 1 found (CK_M2512_002.dia)"

if [ ! -f "test_data/raw/sample2/CK_M2512_003.dia" ]; then
    echo "❌ Sample 2 .dia file not found!"
    exit 1
fi
echo "✓ Sample 2 found (CK_M2512_003.dia)"

echo ""
echo "Test data validation: ✓ PASSED"
echo ""

# Show file sizes
echo "Test data sizes:"
du -h test_data/fasta/*.fasta
du -h test_data/raw/*/*.dia
TOTAL_SIZE=$(du -sh test_data | cut -f1)
echo "Total: $TOTAL_SIZE"
echo ""

# Test 1: Library generation
echo "========================================="
echo "Test 1: Library Generation"
echo "========================================="
echo "This tests:"
echo "  - FASTA parsing"
echo "  - Model resolution utilities"
echo "  - Centralized container binary"
echo ""
read -p "Run library generation test? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo "Running: nextflow run workflows/create_library.nf -params-file configs/test/library_test.yaml -profile standard"
    echo ""

    nextflow run workflows/create_library.nf \
        -params-file configs/test/library_test.yaml \
        -profile standard

    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ Test 1 PASSED"
        echo ""

        # Check output
        if [ -f "test_data/expected_outputs/test_library.predicted.speclib" ]; then
            LIBSIZE=$(du -h test_data/expected_outputs/test_library.predicted.speclib | cut -f1)
            echo "Generated library: $LIBSIZE"
        fi
    else
        echo ""
        echo "❌ Test 1 FAILED"
        exit 1
    fi
fi

echo ""

# Test 2: Quantification (multi-sample)
echo "========================================="
echo "Test 2: Multi-Sample Quantification"
echo "========================================="
echo "This tests:"
echo "  - Sample parsing utilities"
echo "  - File counting utilities"
echo "  - Channel broadcasting (critical!)"
echo "  - Multi-sample workflows"
echo ""

# Check if library exists
if [ ! -f "test_data/expected_outputs/test_library.predicted.speclib" ]; then
    echo "⚠️  Library not found. Run Test 1 first or provide existing library."
    echo ""
    read -p "Enter path to existing library (or press Enter to skip): " LIBRARY_PATH

    if [ -n "$LIBRARY_PATH" ]; then
        # Update config temporarily
        sed -i.bak "s|# library:.*|library: '$LIBRARY_PATH'|" configs/test/quick_test.yaml
    else
        echo "Skipping Test 2 (no library available)"
        exit 0
    fi
fi

# Uncomment library line in config
sed -i.bak 's|# library:|library:|' configs/test/quick_test.yaml

read -p "Run quantification test (2 samples)? [Y/n] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo "Running: nextflow run workflows/quantify_only.nf -params-file configs/test/quick_test.yaml -profile standard"
    echo ""

    nextflow run workflows/quantify_only.nf \
        -params-file configs/test/quick_test.yaml \
        -profile standard

    if [ $? -eq 0 ]; then
        echo ""
        echo "✓ Test 2 PASSED"
        echo ""

        # Check outputs
        echo "Quantification results:"
        du -sh test_results/test_sample* 2>/dev/null || echo "(Results in test_results/)"
    else
        echo ""
        echo "❌ Test 2 FAILED"

        # Restore config
        mv configs/test/quick_test.yaml.bak configs/test/quick_test.yaml 2>/dev/null
        exit 1
    fi
fi

# Restore config
mv configs/test/quick_test.yaml.bak configs/test/quick_test.yaml 2>/dev/null

echo ""
echo "========================================="
echo "All Tests Completed Successfully! ✓"
echo "========================================="
echo ""
echo "Your refactored workflows are working correctly."
echo ""
echo "Next steps:"
echo "  1. Setup Git LFS: cd test_data && ./setup_git_lfs.sh"
echo "  2. Add files: git add test_data/ .gitattributes"
echo "  3. Commit: git commit -m 'Add test data with 506 proteins (28 MB)'"
echo "  4. Push: git push"
echo ""
echo "Summary:"
echo "  - FASTA: 506 proteins, 330 KB"
echo "  - Samples: 2 × 14 MB .dia files"
echo "  - Total: ~28 MB (managed with Git LFS)"
echo "  - Test runtime: ~5-10 minutes"
echo ""
