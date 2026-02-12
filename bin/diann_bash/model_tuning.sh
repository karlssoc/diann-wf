#!/usr/bin/env bash
# Manual DIA-NN model tuning script
#
# Tunes prediction models (RT, IM, FR) using an out-lib from a previous
# quantification run. This is for manual tuning outside of Nextflow.
#
# The out-lib.parquet (or .tsv) from a quantification run is used as input
# for --tune-lib. The report.log.txt from the same run is copied alongside
# the tuning output as provenance (tune_input.log.txt).

set -e

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Tune DIA-NN prediction models using a quantification out-lib.

Options:
    -s SOURCE_DIR    Directory containing out-lib.parquet from quantification
                     Must also contain report.log.txt for provenance
    -o OUTPUT_DIR    Output directory for tuning results
                     (default: results/manual_tuning)
    -m MODE          Tuning mode (default: rt-im)
                       rt       Retention time only (--tune-rt)
                       rt-im    Retention time + ion mobility (--tune-rt --tune-im)
                       all      RT + IM + fragmentation (--tune-rt --tune-im --tune-fr)
    -t THREADS       Number of threads (default: 60)
    -v VERSION       DIA-NN version for binary name (default: 2.3.2)
                     Binary called as: diann-{VERSION}
    -h               Show this help

Examples:
    # RT-only tuning
    $(basename "$0") -s results/quant/sample1 -m rt

    # RT + IM tuning (default mode)
    $(basename "$0") -s results/quant/sample1 -o results/tuning/sample1

    # Full tuning with specific DIA-NN version
    $(basename "$0") -s results/quant/sample1 -m all -v 2.3.2

Output:
    OUTPUT_DIR/
    ├── out-lib.dict.txt          # Token dictionary (always)
    ├── out-lib.tuned_rt.pt       # RT model (if rt mode)
    ├── out-lib.tuned_im.pt       # IM model (if rt-im or all mode)
    ├── out-lib.tuned_fr.pt       # FR model (if all mode)
    ├── tune.log                  # Tuning log (DIA-NN output)
    └── tune_input.log.txt        # Provenance: report.log.txt from quantification
EOF
    exit 1
}

# Defaults
SOURCE_DIR=""
OUTPUT_DIR="results/manual_tuning"
MODE="rt-im"
THREADS=60
DIANN_VERSION="2.3.2"

while getopts "s:o:m:t:v:h" opt; do
    case $opt in
        s) SOURCE_DIR="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        m) MODE="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        v) DIANN_VERSION="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate required arguments
if [ -z "$SOURCE_DIR" ]; then
    echo "ERROR: -s SOURCE_DIR is required"
    echo ""
    usage
fi

if [ ! -d "$SOURCE_DIR" ]; then
    echo "ERROR: Source directory not found: $SOURCE_DIR"
    exit 1
fi

# Validate mode
case "$MODE" in
    rt)    TUNE_FLAGS="--tune-rt" ;;
    rt-im) TUNE_FLAGS="--tune-rt --tune-im" ;;
    all)   TUNE_FLAGS="--tune-rt --tune-im --tune-fr" ;;
    *)
        echo "ERROR: Invalid mode '$MODE'. Must be: rt, rt-im, or all"
        exit 1
        ;;
esac

# Auto-detect tuning input library
TUNE_INPUT=""
if [ -f "$SOURCE_DIR/out-lib.parquet" ]; then
    TUNE_INPUT="out-lib.parquet"
elif [ -f "$SOURCE_DIR/out-lib.tsv" ]; then
    TUNE_INPUT="out-lib.tsv"
else
    echo "ERROR: No out-lib.parquet or out-lib.tsv found in $SOURCE_DIR"
    echo "This file is produced by DIA-NN quantification with --out-lib and --reanalyse (MBR)"
    exit 1
fi

# Check for DIA-NN binary
DIANN_CMD="diann-${DIANN_VERSION}"
if ! command -v "$DIANN_CMD" &> /dev/null; then
    echo "ERROR: DIA-NN binary not found: $DIANN_CMD"
    echo "Ensure DIA-NN ${DIANN_VERSION} is installed and in PATH"
    exit 1
fi

# Setup output directory
mkdir -p "$OUTPUT_DIR"

echo "========================================"
echo "DIA-NN Model Tuning"
echo "========================================"
echo "Source:    $SOURCE_DIR"
echo "Input:     $TUNE_INPUT"
echo "Output:    $OUTPUT_DIR"
echo "Mode:      $MODE ($TUNE_FLAGS)"
echo "Threads:   $THREADS"
echo "DIA-NN:    $DIANN_CMD"
echo ""

# Copy/link tuning input
ln -f "$SOURCE_DIR/$TUNE_INPUT" "$OUTPUT_DIR/$TUNE_INPUT" 2>/dev/null \
    || cp "$SOURCE_DIR/$TUNE_INPUT" "$OUTPUT_DIR/$TUNE_INPUT"
echo "Linked tuning input: $TUNE_INPUT"

# Copy report.log.txt as provenance (tune_input.log.txt)
if [ -f "$SOURCE_DIR/report.log.txt" ]; then
    cp "$SOURCE_DIR/report.log.txt" "$OUTPUT_DIR/tune_input.log.txt"
    echo "Copied provenance:   report.log.txt -> tune_input.log.txt"
else
    echo "WARNING: report.log.txt not found in $SOURCE_DIR (provenance will be missing)"
fi

echo ""
echo "Starting tuning..."
echo ""

# Run DIA-NN tuning
$DIANN_CMD \
    --threads "$THREADS" \
    --tune-lib "$OUTPUT_DIR/$TUNE_INPUT" \
    $TUNE_FLAGS \
    2>&1 | tee "$OUTPUT_DIR/tune.log"

echo ""
echo "========================================"
echo "Tuning Complete"
echo "========================================"

# Show what was produced
echo "Output files:"
for f in "$OUTPUT_DIR"/*.dict.txt "$OUTPUT_DIR"/*.tuned_rt.pt "$OUTPUT_DIR"/*.tuned_im.pt "$OUTPUT_DIR"/*.tuned_fr.pt; do
    if [ -f "$f" ] && [ -s "$f" ]; then
        size=$(du -h "$f" | cut -f1)
        echo "  $(basename "$f")  ($size)"
    fi
done

echo ""
echo "Next steps:"
echo "  1. Collect models into repository:"
echo "     bin/collect_models.sh -s $OUTPUT_DIR -n {instrument}-{lc}-{method}-${DIANN_VERSION}-$(date +%y%m%d)"
echo "  2. Test with: nextflow run karlssoc/diann-wf -entry create_library --model_preset {name} -profile standard"
