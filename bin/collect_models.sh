#!/usr/bin/env bash
# Helper script to collect and organize pre-trained DIA-NN models
# This script searches for model files in DIA-NN output directories and
# organizes them into the repository structure with metadata

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${SCRIPT_DIR}/../models"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Collect and organize pre-trained DIA-NN models into repository structure.
Supports both local and remote (SSH) paths.

Options:
    -s SOURCE_DIR    Source directory containing DIA-NN output
                     Local:  /path/to/tuning
                     Remote: user@host:/path/to/tuning
    -n NAME          Model preset name (e.g., 'ttht-evos-30spd')
    -o OUTPUT_DIR    Output directory (default: models/)
    -h               Show this help

Examples:
    # Collect models from local DIA-NN tuning output
    $0 -s results/tuning/ -n ttht-evos-30spd

    # Collect models from remote server via SSH
    $0 -s kraken:/home/karlssoc/results/tuning -n ttht-evos-30spd

    # Specify custom output location
    $0 -s user@server:/path/to/tuning -n hfx-vneo-30spd -o custom_models/

The script will:
1. Search for model files (dict.txt, tuned_*.pt) in SOURCE_DIR
2. Copy them to OUTPUT_DIR/NAME/
3. Create a metadata.yaml template for you to fill in
4. Update models/instrument_configs.yaml with the new preset

Model files searched for:
- *.dict.txt or dict.txt          → dict.txt (tokens/dictionary)
- *tuned_rt.pt or tuned_rt.pt     → tuned_rt.pt (retention time model)
- *tuned_im.pt or tuned_im.pt     → tuned_im.pt (ion mobility model)
- *tuned_fr.pt or tuned_fr.pt     → tuned_fr.pt (fragmentation model)
- *tune*.log or tune.log          → tune.log (tuning log file, optional)

Naming convention for presets:
Use lowercase with hyphens: {instrument}-{lc}-{method}
Examples: ttht-evos-30spd, hfx-vneo-30spd, astral-evos-60spd
EOF
    exit 1
}

# Parse arguments
SOURCE_DIR=""
MODEL_NAME=""
OUTPUT_DIR="${MODELS_DIR}"

while getopts "s:n:o:h" opt; do
    case $opt in
        s) SOURCE_DIR="$OPTARG" ;;
        n) MODEL_NAME="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate inputs
if [ -z "$SOURCE_DIR" ] || [ -z "$MODEL_NAME" ]; then
    echo "ERROR: -s SOURCE_DIR and -n NAME are required"
    echo ""
    usage
fi

# Detect if SOURCE_DIR is remote (SSH path)
IS_REMOTE=false
SSH_HOST=""
REMOTE_PATH=""

if [[ "$SOURCE_DIR" == *":"* ]]; then
    IS_REMOTE=true
    SSH_HOST="${SOURCE_DIR%%:*}"
    REMOTE_PATH="${SOURCE_DIR#*:}"

    echo "Detected remote source: $SSH_HOST:$REMOTE_PATH"
    echo "Testing SSH connection..."

    # Test SSH connection
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$SSH_HOST" "exit" 2>/dev/null; then
        echo "ERROR: Cannot connect to $SSH_HOST via SSH"
        echo "Please ensure:"
        echo "  1. SSH key authentication is set up"
        echo "  2. Host is reachable"
        echo "  3. Host is in ~/.ssh/config (if using alias like 'kraken')"
        exit 1
    fi

    # Verify remote directory exists
    if ! ssh "$SSH_HOST" "test -d '$REMOTE_PATH'" 2>/dev/null; then
        echo "ERROR: Remote directory not found: $SSH_HOST:$REMOTE_PATH"
        exit 1
    fi

    echo "✓ SSH connection successful"
else
    # Local path - validate directory exists
    if [ ! -d "$SOURCE_DIR" ]; then
        echo "ERROR: Source directory not found: $SOURCE_DIR"
        exit 1
    fi
fi

# Validate preset naming convention
if [[ ! "$MODEL_NAME" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    echo "WARNING: Preset name should be lowercase with hyphens (e.g., 'ttht-evos-30spd')"
    echo "         Current name: $MODEL_NAME"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create output directory
TARGET_DIR="${OUTPUT_DIR}/${MODEL_NAME}"
mkdir -p "$TARGET_DIR"

echo "========================================"
echo "DIA-NN Model Collection Script"
echo "========================================"
echo "Source directory: $SOURCE_DIR"
echo "Target directory: $TARGET_DIR"
echo "Preset name:      $MODEL_NAME"
echo ""
echo "Searching for model files..."
echo ""

# Track what we find
found_tokens=false
found_rt=false
found_im=false
found_fr=false
found_log=false

# Function to find and copy file (supports both local and remote sources)
copy_model_file() {
    local pattern=$1
    local target_name=$2
    local optional=$3
    local found_file=""
    local file_size=""

    if [ "$IS_REMOTE" = true ]; then
        # Remote source - use SSH to find file
        # Variables are expanded locally, then passed to remote command
        found_file=$(ssh "$SSH_HOST" "find \"$REMOTE_PATH\" -name \"$pattern\" -type f 2>/dev/null | head -1")

        if [ -n "$found_file" ]; then
            # Get file size from remote
            file_size=$(ssh "$SSH_HOST" "du -h \"$found_file\" 2>/dev/null | cut -f1")
            echo "  ✓ Found: $SSH_HOST:$found_file ($file_size)"

            # Use rsync to copy file
            if rsync -a "${SSH_HOST}:${found_file}" "${TARGET_DIR}/${target_name}" 2>/dev/null; then
                echo "    → Copied to: ${target_name}"
                return 0
            else
                echo "    ✗ Failed to copy file"
                return 1
            fi
        fi
    else
        # Local source - use find
        found_file=$(find "$SOURCE_DIR" -name "$pattern" -type f 2>/dev/null | head -1)

        if [ -n "$found_file" ]; then
            file_size=$(du -h "$found_file" | cut -f1)
            echo "  ✓ Found: $found_file ($file_size)"
            cp "$found_file" "${TARGET_DIR}/${target_name}"
            echo "    → Copied to: ${target_name}"
            return 0
        fi
    fi

    # File not found
    if [ "$optional" != "true" ]; then
        echo "  ✗ Not found: $pattern"
        return 1
    else
        echo "  - Optional file not found: $pattern"
        return 0
    fi
}

# Search and copy model files
# Tokens file (required)
echo "[1/5] Searching for tokens/dictionary file..."
if copy_model_file "*.dict.txt" "dict.txt" false || copy_model_file "dict.txt" "dict.txt" false; then
    found_tokens=true
else
    echo ""
    echo "ERROR: Token dictionary file not found!"
    echo "Expected to find: *.dict.txt or dict.txt"
    echo ""
    echo "This file is required for model presets. Please check the source directory."
    exit 1
fi

echo ""

# RT model (optional)
echo "[2/5] Searching for retention time model..."
if copy_model_file "*tuned_rt.pt" "tuned_rt.pt" true || copy_model_file "tuned_rt.pt" "tuned_rt.pt" true; then
    found_rt=true
fi

echo ""

# IM model (optional)
echo "[3/5] Searching for ion mobility model..."
if copy_model_file "*tuned_im.pt" "tuned_im.pt" true || copy_model_file "tuned_im.pt" "tuned_im.pt" true; then
    found_im=true
fi

echo ""

# FR model (optional)
echo "[4/5] Searching for fragmentation model..."
if copy_model_file "*tuned_fr.pt" "tuned_fr.pt" true || copy_model_file "tuned_fr.pt" "tuned_fr.pt" true; then
    found_fr=true
fi

echo ""

# Tuning log (optional but recommended)
echo "[5/5] Searching for tuning log file..."
if copy_model_file "*tune*.log" "tune.log" true || copy_model_file "tune.log" "tune.log" true; then
    found_log=true
fi

echo ""
echo "========================================"
echo "Summary"
echo "========================================"
echo "Models collected:"
echo "  Tokens (dict.txt):  $([ "$found_tokens" = true ] && echo "✓" || echo "✗")"
echo "  RT model:           $([ "$found_rt" = true ] && echo "✓" || echo "✗")"
echo "  IM model:           $([ "$found_im" = true ] && echo "✓" || echo "✗")"
echo "  FR model:           $([ "$found_fr" = true ] && echo "✓" || echo "✗")"
echo "  Tuning log:         $([ "$found_log" = true ] && echo "✓" || echo "✗")"
echo ""

# Create metadata template
METADATA_FILE="${TARGET_DIR}/metadata.yaml"
if [ ! -f "$METADATA_FILE" ]; then
    echo "Creating metadata template..."
    cat > "$METADATA_FILE" <<EOF
# Metadata for ${MODEL_NAME} pre-trained models
# Please fill in the details below

# ============================================================================
# INSTRUMENT CONFIGURATION
# ============================================================================

instrument: "INSTRUMENT_NAME"
# Full name of the mass spectrometer
# Examples: "Bruker timsTOF HT", "Thermo Orbitrap Astral", "Thermo HFX"

lc_system: "LC_SYSTEM_NAME"
# Liquid chromatography system
# Examples: "Evosep One", "Vanquish Neo", "UltiMate 3000"

method: "METHOD_DESCRIPTION"
# LC method details
# Examples: "30 SPD (samples per day)", "60 min gradient", "15 min µPAC"

gradient_length_min: 0.0
# Total gradient length in minutes

# ============================================================================
# TRAINING DETAILS
# ============================================================================

diann_version_trained: "2.3.1"
training_date: "$(date +%Y-%m-%d)"
training_library: "LIBRARY_NAME"
# Example: "UniProt Human 2025-11"

training_samples: 0
training_sample_ids: []
# Example:
# - "sample_01"
# - "sample_02"

# ============================================================================
# LIBRARY GENERATION PARAMETERS
# ============================================================================

library_params:
  min_fr_mz: 200
  max_fr_mz: 1800
  min_pep_len: 7
  max_pep_len: 30
  min_pr_mz: 350
  max_pr_mz: 1650
  min_pr_charge: 2
  max_pr_charge: 3
  cut: "K*,R*"
  missed_cleavages: 1
  met_excision: true
  unimod4: true

# ============================================================================
# MODEL FILES
# ============================================================================

models_present:
  tokens: ${found_tokens}
  rt_model: ${found_rt}
  im_model: ${found_im}
  fr_model: ${found_fr}
  tune_log: ${found_log}

# ============================================================================
# VALIDATION & NOTES
# ============================================================================

validated: false
# Set to true after testing on independent samples

validation_notes: ""
# Document validation results here

notes: |
  Add detailed notes about:
  - Training conditions (sample types, preparation)
  - Expected performance improvements
  - Recommended use cases
  - Any limitations

# ============================================================================
# METADATA
# ============================================================================

created_by: "${USER}"
created_date: "$(date +%Y-%m-%d)"
last_updated: "$(date +%Y-%m-%d)"
version: "1.0"
EOF
    echo "  ✓ Created: $METADATA_FILE"
else
    echo "  ⚠ Metadata file already exists: $METADATA_FILE"
fi

echo ""
echo "========================================"
echo "Next Steps"
echo "========================================"
echo "1. Edit metadata file with model details:"
echo "   nano $METADATA_FILE"
echo ""
echo "2. Test the preset:"
echo "   nextflow run workflows/create_library.nf \\"
echo "     --fasta test.fasta \\"
echo "     --library_name test \\"
echo "     --model_preset ${MODEL_NAME} \\"
echo "     -profile standard"
echo ""
echo "3. Validate with real data and update metadata:"
echo "   - Test on independent samples"
echo "   - Compare with default models"
echo "   - Set validated: true if results are good"
echo ""
echo "4. Update the preset index (optional):"
echo "   Edit models/instrument_configs.yaml to add your preset"
echo ""
echo "5. Commit to repository:"
echo "   git add models/${MODEL_NAME}"
echo "   git commit -m \"Add pre-trained models for ${MODEL_NAME}\""
echo ""
echo "Collection complete!"
