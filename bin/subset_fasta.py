#!/usr/bin/env python3
"""
Subset a FASTA file to proteins identified in a DIA-NN parquet report.

Extracts unique protein accessions from the Protein.Group column
(splitting semicolon-delimited groups) and writes a filtered FASTA.

Python equivalent of scripts/subset_fasta.R, using duckdb instead of Biostrings.

Usage:
    python bin/subset_fasta.py -f input.fasta -p report.parquet -o subset.fasta
    python bin/subset_fasta.py -f input.fasta -p r1.parquet r2.parquet -o subset.fasta
"""

import argparse
import sys
from pathlib import Path

try:
    import duckdb
except ImportError:
    print("ERROR: duckdb is required. Install with: pip install duckdb", file=sys.stderr)
    sys.exit(1)


def extract_protein_ids(parquet_files):
    """Extract unique protein accessions from Protein.Group column in parquet files."""
    parquet_list = ', '.join(f"'{p}'" for p in parquet_files)
    con = duckdb.connect()
    rows = con.execute(f"""
        SELECT DISTINCT "Protein.Group"
        FROM read_parquet([{parquet_list}])
        WHERE "Protein.Group" IS NOT NULL
          AND "Protein.Group" != ''
    """).fetchall()
    con.close()

    ids = set()
    for row in rows:
        for accession in row[0].split(';'):
            accession = accession.strip()
            if accession:
                ids.add(accession)
    return ids


def subset_fasta(fasta_path, protein_ids, output_path):
    """Write a filtered FASTA containing only sequences matching protein_ids.

    Supports UniProt headers (>sp|ACCESSION|GENE, >tr|ACCESSION|GENE)
    and plain headers (>ACCESSION description).
    """
    written = 0
    write = False
    with open(fasta_path) as f, open(output_path, 'w') as out:
        for line in f:
            if line.startswith('>'):
                # First whitespace-separated token after '>'
                header_token = line[1:].split()[0]
                parts = header_token.split('|')
                accession = parts[1] if len(parts) >= 2 else parts[0]
                write = accession in protein_ids
                if write:
                    written += 1
            if write:
                out.write(line)
    return written


def main():
    parser = argparse.ArgumentParser(
        description='Subset a FASTA file by protein IDs from a DIA-NN parquet report'
    )
    parser.add_argument('-f', '--fasta', type=Path, required=True,
                        help='Input FASTA file')
    parser.add_argument('-p', '--parquet', type=Path, nargs='+', required=True,
                        help='Input parquet file(s) with Protein.Group column')
    parser.add_argument('-o', '--output', type=Path, required=True,
                        help='Output FASTA file')

    args = parser.parse_args()

    if not args.fasta.exists():
        print(f"ERROR: FASTA file not found: {args.fasta}", file=sys.stderr)
        sys.exit(1)
    for p in args.parquet:
        if not p.exists():
            print(f"ERROR: Parquet file not found: {p}", file=sys.stderr)
            sys.exit(1)

    print(f"Extracting protein IDs from {len(args.parquet)} parquet file(s)...")
    protein_ids = extract_protein_ids([str(p) for p in args.parquet])
    print(f"Unique protein IDs: {len(protein_ids)}")

    if not protein_ids:
        print("ERROR: No protein IDs found in parquet file(s)", file=sys.stderr)
        sys.exit(1)

    input_seqs = sum(1 for line in open(args.fasta) if line.startswith('>'))
    print(f"Input FASTA sequences: {input_seqs}")

    written = subset_fasta(args.fasta, protein_ids, args.output)
    print(f"Output FASTA sequences: {written}")

    if input_seqs > 0:
        reduction = (1 - written / input_seqs) * 100
        print(f"Reduction: {reduction:.1f}%")

    print(f"Written to: {args.output}")


if __name__ == '__main__':
    main()
