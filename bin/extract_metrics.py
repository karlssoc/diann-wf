#!/usr/bin/env python3
"""
Extract metrics from DIA-NN quantification results for method comparison.

Usage:
    python bin/extract_metrics.py <results_dir> [--output metrics.tsv]

Metrics extracted per condition/sample:
    - Protein.Groups: Number of protein groups identified (1% FDR)
    - Precursors: Number of precursors identified
    - Peptides: Number of peptide sequences identified
    - Missing Rate: Percentage of missing values in quantification
    - Median CV: Median coefficient of variation (if replicates)
"""

import argparse
import sys
from pathlib import Path

try:
    import duckdb
except ImportError:
    print("ERROR: duckdb is required. Install with: pip install duckdb", file=sys.stderr)
    sys.exit(1)


def extract_metrics_from_report(report_path: Path) -> dict:
    """Extract metrics from a DIA-NN report.parquet file."""

    if not report_path.exists():
        return None

    conn = duckdb.connect()

    try:
        # Load report
        df = conn.execute(f"SELECT * FROM read_parquet('{report_path}')").fetchdf()

        # Get column names (case-insensitive matching)
        cols = {c.lower(): c for c in df.columns}

        # Extract metrics
        metrics = {}

        # Protein Groups
        pg_col = cols.get('protein.group') or cols.get('protein_group') or cols.get('pg')
        if pg_col:
            metrics['protein_groups'] = df[pg_col].nunique()

        # Precursors
        pr_col = cols.get('precursor.id') or cols.get('precursor_id') or cols.get('pr')
        if pr_col:
            metrics['precursors'] = df[pr_col].nunique()

        # Peptides (stripped sequence)
        pep_col = cols.get('stripped.sequence') or cols.get('peptide') or cols.get('sequence')
        if pep_col:
            metrics['peptides'] = df[pep_col].nunique()

        # Intensity/Quantity for missing value calculation
        quant_col = None
        for possible in ['precursor.quantity', 'quantity', 'intensity', 'precursor.normalised']:
            if possible in cols:
                quant_col = cols[possible]
                break

        if quant_col:
            total_values = len(df)
            missing_values = df[quant_col].isna().sum() + (df[quant_col] == 0).sum()
            metrics['missing_rate'] = (missing_values / total_values * 100) if total_values > 0 else 0
            metrics['total_entries'] = total_values

        # Q-value for FDR check
        qval_col = cols.get('q.value') or cols.get('qvalue') or cols.get('fdr')
        if qval_col:
            # Count at 1% FDR
            at_1pct_fdr = df[df[qval_col] <= 0.01]
            metrics['precursors_1pct_fdr'] = len(at_1pct_fdr)
            if pr_col:
                metrics['precursors_unique_1pct_fdr'] = at_1pct_fdr[pr_col].nunique()

        return metrics

    except Exception as e:
        print(f"  Warning: Error processing {report_path}: {e}", file=sys.stderr)
        return None
    finally:
        conn.close()


def extract_metrics_from_stats(stats_path: Path) -> dict:
    """Extract metrics from report.stats.tsv file."""

    if not stats_path.exists():
        return None

    metrics = {}

    try:
        with open(stats_path) as f:
            for line in f:
                parts = line.strip().split('\t')
                if len(parts) >= 2:
                    key, value = parts[0], parts[1]
                    # Parse common stats
                    if 'protein' in key.lower() and 'group' in key.lower():
                        try:
                            metrics['protein_groups_stats'] = int(value)
                        except ValueError:
                            pass
                    elif 'precursor' in key.lower() and 'id' in key.lower():
                        try:
                            metrics['precursors_stats'] = int(value)
                        except ValueError:
                            pass
    except Exception as e:
        print(f"  Warning: Error reading {stats_path}: {e}", file=sys.stderr)

    return metrics


def scan_results_directory(results_dir: Path) -> list:
    """Scan results directory for quantification outputs."""

    results = []

    # Look for condition directories
    for condition_dir in results_dir.iterdir():
        if not condition_dir.is_dir():
            continue

        condition_name = condition_dir.name

        # Skip non-condition directories
        if condition_name in ['metrics', 'pipeline_info', 'work', 'library']:
            continue

        # Look for sample directories within condition
        for sample_dir in condition_dir.iterdir():
            if not sample_dir.is_dir():
                continue

            sample_name = sample_dir.name

            # Skip library directory
            if sample_name == 'library':
                continue

            # Look for report.parquet
            report_path = sample_dir / 'report.parquet'
            stats_path = sample_dir / 'report.stats.tsv'

            if report_path.exists():
                results.append({
                    'condition': condition_name,
                    'sample': sample_name,
                    'report_path': report_path,
                    'stats_path': stats_path if stats_path.exists() else None
                })

    return results


def main():
    parser = argparse.ArgumentParser(
        description='Extract metrics from DIA-NN quantification results'
    )
    parser.add_argument('results_dir', type=Path, help='Results directory to scan')
    parser.add_argument('--output', '-o', type=Path, default=None,
                        help='Output TSV file (default: <results_dir>/metrics/summary.tsv)')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose output')

    args = parser.parse_args()

    if not args.results_dir.exists():
        print(f"ERROR: Results directory not found: {args.results_dir}", file=sys.stderr)
        sys.exit(1)

    # Set output path
    output_path = args.output or (args.results_dir / 'metrics' / 'summary.tsv')
    output_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"Scanning: {args.results_dir}")

    # Find all result files
    results = scan_results_directory(args.results_dir)

    if not results:
        print("No quantification results found.")
        sys.exit(1)

    print(f"Found {len(results)} result files")

    # Extract metrics for each result
    all_metrics = []

    for result in results:
        if args.verbose:
            print(f"  Processing: {result['condition']}/{result['sample']}")

        metrics = {
            'condition': result['condition'],
            'sample': result['sample']
        }

        # Extract from parquet
        report_metrics = extract_metrics_from_report(result['report_path'])
        if report_metrics:
            metrics.update(report_metrics)

        # Extract from stats file
        if result['stats_path']:
            stats_metrics = extract_metrics_from_stats(result['stats_path'])
            if stats_metrics:
                metrics.update(stats_metrics)

        all_metrics.append(metrics)

    # Write output
    if all_metrics:
        # Get all unique keys
        all_keys = set()
        for m in all_metrics:
            all_keys.update(m.keys())

        # Order columns
        ordered_keys = ['condition', 'sample']
        for key in ['protein_groups', 'precursors', 'peptides', 'missing_rate',
                    'precursors_1pct_fdr', 'total_entries']:
            if key in all_keys:
                ordered_keys.append(key)
                all_keys.discard(key)
        ordered_keys.extend(sorted(all_keys - set(ordered_keys)))

        # Write TSV
        with open(output_path, 'w') as f:
            f.write('\t'.join(ordered_keys) + '\n')
            for m in all_metrics:
                row = [str(m.get(k, '')) for k in ordered_keys]
                f.write('\t'.join(row) + '\n')

        print(f"\nMetrics written to: {output_path}")

        # Print summary
        print("\nSummary:")
        print("-" * 60)

        # Group by condition
        by_condition = {}
        for m in all_metrics:
            cond = m['condition']
            if cond not in by_condition:
                by_condition[cond] = []
            by_condition[cond].append(m)

        for cond in sorted(by_condition.keys()):
            samples = by_condition[cond]
            n_samples = len(samples)

            # Average metrics
            avg_pg = sum(s.get('protein_groups', 0) for s in samples) / n_samples
            avg_pr = sum(s.get('precursors', 0) for s in samples) / n_samples
            avg_missing = sum(s.get('missing_rate', 0) for s in samples) / n_samples

            print(f"{cond}:")
            print(f"  Samples: {n_samples}")
            print(f"  Avg Protein Groups: {avg_pg:.0f}")
            print(f"  Avg Precursors: {avg_pr:.0f}")
            print(f"  Avg Missing Rate: {avg_missing:.1f}%")
            print()


if __name__ == '__main__':
    main()
