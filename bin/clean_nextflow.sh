#!/bin/bash
# Clean up Nextflow test artifacts and temporary files
# Run this after local testing to restore a clean working directory

set -e

echo "========================================="
echo "Nextflow Cleanup Script"
echo "========================================="
echo ""

# Track what we're cleaning
CLEANED=0

# 1. Clean Nextflow work directory
if [ -d "work" ]; then
    echo "Removing work directory..."
    WORKSIZE=$(du -sh work 2>/dev/null | cut -f1)
    rm -rf work
    echo "  ✓ Removed work/ ($WORKSIZE)"
    CLEANED=1
fi

# 2. Clean Nextflow cache
if [ -d ".nextflow" ]; then
    echo "Removing .nextflow cache..."
    rm -rf .nextflow
    echo "  ✓ Removed .nextflow/"
    CLEANED=1
fi

# 3. Clean Nextflow log files
LOGCOUNT=$(ls -1 .nextflow.log* 2>/dev/null | wc -l | tr -d ' ')
if [ "$LOGCOUNT" -gt 0 ]; then
    echo "Removing Nextflow log files..."
    rm -f .nextflow.log*
    echo "  ✓ Removed $LOGCOUNT log file(s)"
    CLEANED=1
fi

# 4. Clean timeline/report/trace files (if generated)
if [ -f "timeline.html" ] || [ -f "report.html" ] || [ -f "trace.txt" ] || [ -f "dag.dot" ]; then
    echo "Removing execution reports..."
    rm -f timeline.html report.html trace.txt dag.dot
    echo "  ✓ Removed execution reports"
    CLEANED=1
fi

# 5. Clean test results (optional - ask user)
if [ -d "test_results" ]; then
    RESULTSIZE=$(du -sh test_results 2>/dev/null | cut -f1)
    echo ""
    echo "Test results directory found: $RESULTSIZE"
    read -p "Remove test_results/? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf test_results
        echo "  ✓ Removed test_results/ ($RESULTSIZE)"
        CLEANED=1
    else
        echo "  - Kept test_results/"
    fi
fi

# 6. Clean output directories (optional - ask user)
if [ -d "results" ] || [ -d "output" ]; then
    echo ""
    echo "Output directories found"
    read -p "Remove results/output directories? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        [ -d "results" ] && rm -rf results && echo "  ✓ Removed results/"
        [ -d "output" ] && rm -rf output && echo "  ✓ Removed output/"
        CLEANED=1
    else
        echo "  - Kept output directories"
    fi
fi

# 7. Clean backup files created by test script
if ls configs/test/*.yaml.bak 1> /dev/null 2>&1; then
    echo "Removing config backup files..."
    rm -f configs/test/*.yaml.bak
    echo "  ✓ Removed .yaml.bak files"
    CLEANED=1
fi

echo ""
if [ $CLEANED -eq 1 ]; then
    echo "✓ Cleanup complete!"
else
    echo "✓ Nothing to clean (workspace already clean)"
fi
echo ""

# Show disk usage summary
echo "Current disk usage:"
if [ -d "test_data" ]; then
    TESTDATA=$(du -sh test_data 2>/dev/null | cut -f1)
    echo "  test_data/: $TESTDATA"
fi
if [ -d "models" ]; then
    MODELS=$(du -sh models 2>/dev/null | cut -f1)
    echo "  models/: $MODELS"
fi
TOTAL=$(du -sh . 2>/dev/null | cut -f1)
echo "  Total: $TOTAL"
echo ""
