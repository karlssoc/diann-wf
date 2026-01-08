#!/bin/bash
# Sync local changes to kraken for testing

set -e

REMOTE="karlssoc@kraken:/srv/data1/karlssoc/projects/diann-wf"

echo "Syncing to kraken..."
rsync -avz \
  --exclude '.nextflow/' \
  --exclude 'work/' \
  --exclude '.nextflow.log*' \
  --exclude '.git/' \
  --exclude '*.swp' \
  --exclude '.DS_Store' \
  --exclude '__pycache__/' \
  --exclude '*.pyc' \
  --progress \
  ./ "$REMOTE/"

echo ""
echo "✓ Sync complete!"
echo ""
echo "To run tests on kraken:"
echo "  ssh karlssoc@kraken"
echo "  cd /srv/data1/karlssoc/projects/diann-wf"
echo "  ./test.sh"
