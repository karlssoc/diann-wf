#!/bin/bash
#
# qc-watch.sh — cron entry point for the automated MS-QC pipeline.
#
# Wraps bin/qc-watch with:
#   - flock        : a single run at a time (a search can exceed the cron interval)
#   - /dev/shm fix : remove stale Bruker shared-memory maps left by cancelled runs
#                    (see CLAUDE.md "Issue 8"; harmless for Thermo-only setups)
#   - env activation for the Python env that has obtools + duckdb + pyyaml
#
# Deploy (kraken), e.g. poll every 30 min:
#   crontab -e
#   */30 * * * * /home/karlssoc/Projects/Tools/diann-wf/bin/qc-watch.sh
#
# Override defaults via environment in the crontab line if needed:
#   QC_CONFIG=/path/to/qc_watch.yaml  QC_ENV=/path/to/venv  ... qc-watch.sh
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"

# --- configurable via environment -------------------------------------------
QC_CONFIG="${QC_CONFIG:-$REPO/configs/qc/qc_watch.yaml}"
QC_LOG="${QC_LOG:-$HOME/qc-watch.log}"
QC_LOCK="${QC_LOCK:-$HOME/.qc-watch.lock}"
# Optional: a conda/venv to activate so `obtools` and `nextflow` are on PATH.
#   QC_ENV=/path/to/venv            -> sources venv/bin/activate
#   QC_CONDA=qc                     -> conda activate qc
QC_ENV="${QC_ENV:-}"
QC_CONDA="${QC_CONDA:-}"
# ----------------------------------------------------------------------------

# Prevent overlapping runs; exit quietly if a previous run is still going.
exec 9>"$QC_LOCK"
if ! flock -n 9; then
    echo "$(date '+%F %T') qc-watch already running; skipping." >> "$QC_LOG"
    exit 0
fi

{
    echo "==== $(date '+%F %T') qc-watch tick ===="

    # Clear stale Bruker IPC maps from any cancelled DIA-NN run on this node.
    rm -f /dev/shm/bip.gmem.map* 2>/dev/null || true

    if [ -n "$QC_CONDA" ]; then
        # shellcheck disable=SC1091
        source "$(conda info --base)/etc/profile.d/conda.sh" && conda activate "$QC_CONDA"
    elif [ -n "$QC_ENV" ]; then
        # shellcheck disable=SC1091
        source "$QC_ENV/bin/activate"
    fi

    "$HERE/qc-watch" --config "$QC_CONFIG" "$@"
    echo "==== $(date '+%F %T') exit $? ===="
} >> "$QC_LOG" 2>&1
