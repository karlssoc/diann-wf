#!/usr/bin/env python3
"""
Create minimal FASTA file from DIA-NN protein matrix output.

This script extracts protein IDs from DIA-NN results and creates a minimal
FASTA file containing only the proteins actually detected in the test data.

Usage:
    python3 create_minimal_fasta.py \\
        --protein-matrix diann/report.pg_matrix.tsv \\
        --full-fasta /path/to/full_proteome.fasta \\
        --output ../test_data/fasta/minimal_proteome.fasta \\
        --top 500

Options:
    --top N         Include only top N most abundant proteins (optional)
    --min-peptides N  Minimum number of peptides per protein (default: 2)
"""

import argparse
import sys
from pathlib import Path
from typing import Dict, Set, List, Tuple


def parse_protein_matrix(matrix_file: Path, top_n: int = None, min_peptides: int = 2) -> Set[str]:
    """
    Extract protein IDs from DIA-NN protein matrix.

    Args:
        matrix_file: Path to report.pg_matrix.tsv
        top_n: If specified, return only top N most abundant proteins
        min_peptides: Minimum number of peptides to include protein

    Returns:
        Set of protein IDs to include in FASTA
    """
    protein_data = []

    print(f"Reading protein matrix: {matrix_file}")

    with open(matrix_file, 'r') as f:
        header = f.readline().strip().split('\t')

        # Find column indices
        protein_col = header.index('Protein.Group')
        n_seq_col = header.index('N.Sequences')

        # Find intensity columns (sample columns)
        intensity_cols = [i for i, col in enumerate(header) if col.endswith('.dia')]

        if not intensity_cols:
            print("ERROR: No .dia sample columns found in matrix")
            sys.exit(1)

        print(f"Found {len(intensity_cols)} sample columns")

        for line in f:
            fields = line.strip().split('\t')
            protein_id = fields[protein_col]
            n_sequences = int(fields[n_seq_col])

            # Skip proteins with too few peptides
            if n_sequences < min_peptides:
                continue

            # Calculate mean intensity across samples
            intensities = []
            for col_idx in intensity_cols:
                try:
                    val = float(fields[col_idx]) if fields[col_idx] else 0
                    intensities.append(val)
                except (ValueError, IndexError):
                    intensities.append(0)

            mean_intensity = sum(intensities) / len(intensities) if intensities else 0

            protein_data.append((protein_id, mean_intensity, n_sequences))

    print(f"Loaded {len(protein_data)} proteins (≥{min_peptides} peptides)")

    # Sort by abundance
    protein_data.sort(key=lambda x: x[1], reverse=True)

    # Select proteins
    if top_n and top_n < len(protein_data):
        selected = protein_data[:top_n]
        print(f"Selected top {top_n} most abundant proteins")
    else:
        selected = protein_data
        print(f"Selected all {len(selected)} proteins")

    # Extract protein IDs (handle semicolon-separated groups)
    protein_ids = set()
    for protein_group, _, _ in selected:
        # Protein groups may be semicolon-separated
        for protein_id in protein_group.split(';'):
            protein_ids.add(protein_id.strip())

    print(f"Total unique protein IDs: {len(protein_ids)}")
    return protein_ids


def extract_fasta_entries(full_fasta: Path, protein_ids: Set[str]) -> Dict[str, str]:
    """
    Extract FASTA entries for specified protein IDs.

    Args:
        full_fasta: Path to full FASTA file
        protein_ids: Set of protein IDs to extract

    Returns:
        Dictionary mapping protein ID to (header, sequence)
    """
    print(f"\nReading full FASTA: {full_fasta}")

    entries = {}
    current_id = None
    current_header = None
    current_seq = []
    found_count = 0

    with open(full_fasta, 'r') as f:
        for line in f:
            line = line.rstrip()

            if line.startswith('>'):
                # Save previous entry
                if current_id and current_id in protein_ids:
                    entries[current_id] = (current_header, ''.join(current_seq))
                    found_count += 1

                # Start new entry
                current_header = line
                # Extract protein ID (various formats)
                # Format: >sp|P12345|NAME_ORGANISM or >P12345 or >tr|P12345|...
                parts = line[1:].split('|')
                if len(parts) >= 2:
                    current_id = parts[1].split()[0]  # Get ID, remove any trailing info
                else:
                    current_id = line[1:].split()[0]  # Simple format
                current_seq = []
            else:
                current_seq.append(line)

        # Don't forget last entry
        if current_id and current_id in protein_ids:
            entries[current_id] = (current_header, ''.join(current_seq))
            found_count += 1

    print(f"Found {found_count} / {len(protein_ids)} proteins in FASTA")

    if found_count < len(protein_ids):
        missing = protein_ids - set(entries.keys())
        print(f"\nWARNING: {len(missing)} proteins not found in FASTA")
        if len(missing) <= 10:
            print("Missing IDs:", ', '.join(sorted(missing)))

    return entries


def write_minimal_fasta(entries: Dict[str, Tuple[str, str]], output_file: Path):
    """Write minimal FASTA file."""
    output_file.parent.mkdir(parents=True, exist_ok=True)

    print(f"\nWriting minimal FASTA: {output_file}")

    with open(output_file, 'w') as f:
        for protein_id in sorted(entries.keys()):
            header, sequence = entries[protein_id]
            f.write(f"{header}\n")
            # Write sequence in 60-character lines
            for i in range(0, len(sequence), 60):
                f.write(f"{sequence[i:i+60]}\n")

    # Calculate statistics
    total_aa = sum(len(seq) for _, seq in entries.values())
    avg_length = total_aa / len(entries) if entries else 0

    print(f"\nFASTA Statistics:")
    print(f"  Proteins: {len(entries)}")
    print(f"  Total amino acids: {total_aa:,}")
    print(f"  Average protein length: {avg_length:.0f} aa")
    print(f"  File size: ~{(output_file.stat().st_size / 1024):.1f} KB")


def main():
    parser = argparse.ArgumentParser(
        description='Create minimal FASTA from DIA-NN protein matrix',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument('--protein-matrix', required=True,
                       help='DIA-NN protein matrix (report.pg_matrix.tsv)')
    parser.add_argument('--full-fasta', required=True,
                       help='Full FASTA file containing all proteins')
    parser.add_argument('--output', required=True,
                       help='Output minimal FASTA file')
    parser.add_argument('--top', type=int,
                       help='Include only top N most abundant proteins')
    parser.add_argument('--min-peptides', type=int, default=2,
                       help='Minimum peptides per protein (default: 2)')

    args = parser.parse_args()

    # Validate inputs
    matrix_file = Path(args.protein_matrix)
    full_fasta = Path(args.full_fasta)
    output_file = Path(args.output)

    if not matrix_file.exists():
        print(f"ERROR: Protein matrix not found: {matrix_file}")
        sys.exit(1)

    if not full_fasta.exists():
        print(f"ERROR: Full FASTA not found: {full_fasta}")
        sys.exit(1)

    # Extract protein IDs from DIA-NN results
    protein_ids = parse_protein_matrix(matrix_file, args.top, args.min_peptides)

    if not protein_ids:
        print("ERROR: No proteins selected")
        sys.exit(1)

    # Extract FASTA entries
    entries = extract_fasta_entries(full_fasta, protein_ids)

    if not entries:
        print("ERROR: No FASTA entries found")
        sys.exit(1)

    # Write output
    write_minimal_fasta(entries, output_file)

    print("\nDone!")


if __name__ == '__main__':
    main()
