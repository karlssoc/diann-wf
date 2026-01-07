#!/bin/bash
# Generate minimal FASTA file for test data
# Extracts proteins detected in test .dia files from full proteome FASTA

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Minimal FASTA Generator for Test Data ==="
echo ""

# Check if DIA-NN results exist
if [ ! -f "$SCRIPT_DIR/diann/report.pg_matrix.tsv" ]; then
    echo "ERROR: DIA-NN protein matrix not found!"
    echo "Expected: $SCRIPT_DIR/diann/report.pg_matrix.tsv"
    echo ""
    echo "Please run DIA-NN on your .dia test files first."
    exit 1
fi

# Count detected proteins
PROTEIN_COUNT=$(tail -n +2 "$SCRIPT_DIR/diann/report.pg_matrix.tsv" | wc -l | tr -d ' ')
echo "Detected proteins in test data: $PROTEIN_COUNT"
echo ""

# Ask for full FASTA path
echo "Enter path to your FULL FASTA file (e.g., uniprot_yeast.fasta):"
read -r FULL_FASTA

if [ ! -f "$FULL_FASTA" ]; then
    echo "ERROR: FASTA file not found: $FULL_FASTA"
    exit 1
fi

echo ""
echo "Choose FASTA size option:"
echo "  1) All detected proteins (~${PROTEIN_COUNT} proteins) - Most comprehensive"
echo "  2) Top 500 most abundant proteins - Recommended for testing ⭐"
echo "  3) Top 300 most abundant proteins - Minimal/fastest"
echo "  4) Custom number"
echo ""
read -p "Selection [2]: " CHOICE
CHOICE=${CHOICE:-2}

case $CHOICE in
    1)
        TOP_N=""
        SIZE_DESC="all $PROTEIN_COUNT"
        ;;
    2)
        TOP_N="--top 500"
        SIZE_DESC="top 500"
        ;;
    3)
        TOP_N="--top 300"
        SIZE_DESC="top 300"
        ;;
    4)
        read -p "Enter number of proteins: " CUSTOM_N
        TOP_N="--top $CUSTOM_N"
        SIZE_DESC="top $CUSTOM_N"
        ;;
    *)
        echo "Invalid choice, using default (top 500)"
        TOP_N="--top 500"
        SIZE_DESC="top 500"
        ;;
esac

OUTPUT_FASTA="../test_data/fasta/minimal_proteome.fasta"
mkdir -p "$(dirname "$OUTPUT_FASTA")"

echo ""
echo "Generating FASTA with $SIZE_DESC proteins..."
echo ""

python3 "$SCRIPT_DIR/create_minimal_fasta.py" \
    --protein-matrix "$SCRIPT_DIR/diann/report.pg_matrix.tsv" \
    --full-fasta "$FULL_FASTA" \
    --output "$OUTPUT_FASTA" \
    $TOP_N \
    --min-peptides 2

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Success!"
    echo ""
    echo "Minimal FASTA created: $OUTPUT_FASTA"
    echo ""
    echo "Next steps:"
    echo "  1. Copy .dia files to test_data/raw/:"
    echo "     cp generate_example_data/*.dia test_data/raw/sample*/"
    echo ""
    echo "  2. Test library generation:"
    echo "     nextflow run workflows/create_library.nf -params-file configs/test/library_test.yaml"
    echo ""
    echo "  3. Test quantification:"
    echo "     nextflow run workflows/quantify_only.nf -params-file configs/test/quick_test.yaml"
else
    echo ""
    echo "✗ Failed to generate FASTA"
    exit 1
fi
