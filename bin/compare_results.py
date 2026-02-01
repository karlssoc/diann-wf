#!/usr/bin/env python3
"""
Compare DIA-NN quantification results across different conditions.

Usage:
    python bin/compare_results.py <metrics.tsv> [--output comparison.html]

Generates:
    - Comparison table (TSV)
    - HTML report with summary statistics
    - Optional: plots if matplotlib is available
"""

import argparse
import sys
from pathlib import Path
from collections import defaultdict


def load_metrics(metrics_path: Path) -> list:
    """Load metrics from TSV file."""

    metrics = []

    with open(metrics_path) as f:
        header = f.readline().strip().split('\t')

        for line in f:
            values = line.strip().split('\t')
            row = dict(zip(header, values))

            # Convert numeric values
            for key in row:
                if key not in ['condition', 'sample']:
                    try:
                        if '.' in row[key]:
                            row[key] = float(row[key])
                        else:
                            row[key] = int(row[key])
                    except (ValueError, TypeError):
                        pass

            metrics.append(row)

    return metrics


def calculate_statistics(metrics: list) -> dict:
    """Calculate summary statistics by condition."""

    by_condition = defaultdict(list)
    for m in metrics:
        by_condition[m['condition']].append(m)

    stats = {}

    for cond, samples in by_condition.items():
        n = len(samples)
        stats[cond] = {
            'n_samples': n,
            'conditions': cond
        }

        # Calculate mean for numeric columns
        numeric_keys = [k for k in samples[0].keys() if k not in ['condition', 'sample']
                        and isinstance(samples[0].get(k), (int, float))]

        for key in numeric_keys:
            values = [s[key] for s in samples if isinstance(s.get(key), (int, float))]
            if values:
                stats[cond][f'{key}_mean'] = sum(values) / len(values)
                stats[cond][f'{key}_min'] = min(values)
                stats[cond][f'{key}_max'] = max(values)
                if len(values) > 1:
                    mean = stats[cond][f'{key}_mean']
                    variance = sum((x - mean) ** 2 for x in values) / (len(values) - 1)
                    stats[cond][f'{key}_std'] = variance ** 0.5

    return stats


def generate_comparison_table(stats: dict, baseline: str = None) -> str:
    """Generate comparison table with optional relative differences."""

    lines = []

    # Determine baseline
    if baseline is None:
        # Use 'standard_default' or first condition as baseline
        if 'standard_default' in stats:
            baseline = 'standard_default'
        else:
            baseline = list(stats.keys())[0]

    # Header
    conditions = sorted(stats.keys())
    metrics_to_show = ['protein_groups', 'precursors', 'peptides', 'missing_rate']

    lines.append("\nComparison Table (vs baseline: {})".format(baseline))
    lines.append("=" * 70)

    # Column header
    header = ['Metric'] + conditions
    lines.append('\t'.join(header))
    lines.append('-' * 70)

    # Rows
    for metric in metrics_to_show:
        row = [metric]
        baseline_val = stats.get(baseline, {}).get(f'{metric}_mean')

        for cond in conditions:
            val = stats.get(cond, {}).get(f'{metric}_mean')
            if val is not None:
                if cond == baseline:
                    row.append(f"{val:.1f}")
                elif baseline_val and baseline_val != 0:
                    diff_pct = (val - baseline_val) / baseline_val * 100
                    sign = '+' if diff_pct > 0 else ''
                    row.append(f"{val:.1f} ({sign}{diff_pct:.1f}%)")
                else:
                    row.append(f"{val:.1f}")
            else:
                row.append('N/A')

        lines.append('\t'.join(row))

    return '\n'.join(lines)


def generate_html_report(stats: dict, metrics: list, output_path: Path, baseline: str = None):
    """Generate HTML comparison report."""

    if baseline is None:
        if 'standard_default' in stats:
            baseline = 'standard_default'
        else:
            baseline = list(stats.keys())[0]

    conditions = sorted(stats.keys())
    metrics_to_show = ['protein_groups', 'precursors', 'peptides', 'missing_rate']

    html = """<!DOCTYPE html>
<html>
<head>
    <title>DIA-NN Method Comparison</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 40px; }
        h1 { color: #333; }
        h2 { color: #666; margin-top: 30px; }
        table { border-collapse: collapse; margin: 20px 0; }
        th, td { border: 1px solid #ddd; padding: 12px; text-align: right; }
        th { background-color: #f5f5f5; }
        td:first-child { text-align: left; font-weight: bold; }
        .baseline { background-color: #e8f4fc; }
        .positive { color: #28a745; }
        .negative { color: #dc3545; }
        .summary { background-color: #f9f9f9; padding: 20px; border-radius: 8px; margin: 20px 0; }
        .metric-card { display: inline-block; margin: 10px; padding: 20px; background: white; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); min-width: 150px; }
        .metric-value { font-size: 24px; font-weight: bold; color: #333; }
        .metric-label { font-size: 12px; color: #666; margin-top: 5px; }
    </style>
</head>
<body>
    <h1>DIA-NN Method Comparison Report</h1>
    <p>Baseline condition: <strong>{baseline}</strong></p>

    <div class="summary">
        <h2>Summary</h2>
""".format(baseline=baseline)

    # Add summary cards
    for cond in conditions:
        s = stats[cond]
        pg = s.get('protein_groups_mean', 0)
        pr = s.get('precursors_mean', 0)
        html += f"""
        <div class="metric-card">
            <div class="metric-value">{pg:.0f}</div>
            <div class="metric-label">{cond}<br>Protein Groups</div>
        </div>
"""

    html += """
    </div>

    <h2>Detailed Comparison</h2>
    <table>
        <thead>
            <tr>
                <th>Metric</th>
"""

    for cond in conditions:
        class_name = 'baseline' if cond == baseline else ''
        html += f'                <th class="{class_name}">{cond}</th>\n'

    html += """            </tr>
        </thead>
        <tbody>
"""

    # Table rows
    for metric in metrics_to_show:
        metric_label = metric.replace('_', ' ').title()
        html += f'            <tr>\n                <td>{metric_label}</td>\n'

        baseline_val = stats.get(baseline, {}).get(f'{metric}_mean')

        for cond in conditions:
            val = stats.get(cond, {}).get(f'{metric}_mean')
            class_name = 'baseline' if cond == baseline else ''

            if val is not None:
                if cond == baseline:
                    html += f'                <td class="{class_name}">{val:.1f}</td>\n'
                elif baseline_val and baseline_val != 0:
                    diff_pct = (val - baseline_val) / baseline_val * 100
                    # For missing_rate, lower is better
                    if metric == 'missing_rate':
                        diff_class = 'positive' if diff_pct < 0 else 'negative'
                    else:
                        diff_class = 'positive' if diff_pct > 0 else 'negative'
                    sign = '+' if diff_pct > 0 else ''
                    html += f'                <td class="{diff_class}">{val:.1f} ({sign}{diff_pct:.1f}%)</td>\n'
                else:
                    html += f'                <td>{val:.1f}</td>\n'
            else:
                html += '                <td>N/A</td>\n'

        html += '            </tr>\n'

    html += """        </tbody>
    </table>

    <h2>Per-Sample Results</h2>
    <table>
        <thead>
            <tr>
                <th>Condition</th>
                <th>Sample</th>
                <th>Protein Groups</th>
                <th>Precursors</th>
                <th>Peptides</th>
                <th>Missing Rate (%)</th>
            </tr>
        </thead>
        <tbody>
"""

    for m in sorted(metrics, key=lambda x: (x['condition'], x['sample'])):
        html += f"""            <tr>
                <td>{m['condition']}</td>
                <td>{m['sample']}</td>
                <td>{m.get('protein_groups', 'N/A')}</td>
                <td>{m.get('precursors', 'N/A')}</td>
                <td>{m.get('peptides', 'N/A')}</td>
                <td>{m.get('missing_rate', 'N/A'):.1f if isinstance(m.get('missing_rate'), (int, float)) else 'N/A'}</td>
            </tr>
"""

    html += """        </tbody>
    </table>

    <p style="color: #999; font-size: 12px; margin-top: 40px;">
        Generated by diann-wf/bin/compare_results.py
    </p>
</body>
</html>
"""

    with open(output_path, 'w') as f:
        f.write(html)


def main():
    parser = argparse.ArgumentParser(
        description='Compare DIA-NN quantification results across conditions'
    )
    parser.add_argument('metrics_file', type=Path, help='Metrics TSV file from extract_metrics.py')
    parser.add_argument('--output', '-o', type=Path, default=None,
                        help='Output HTML report path')
    parser.add_argument('--baseline', '-b', type=str, default=None,
                        help='Baseline condition for comparison (default: standard_default)')

    args = parser.parse_args()

    if not args.metrics_file.exists():
        print(f"ERROR: Metrics file not found: {args.metrics_file}", file=sys.stderr)
        sys.exit(1)

    # Load metrics
    metrics = load_metrics(args.metrics_file)

    if not metrics:
        print("No metrics found in file.")
        sys.exit(1)

    print(f"Loaded {len(metrics)} result entries")

    # Calculate statistics
    stats = calculate_statistics(metrics)

    # Print comparison table
    table = generate_comparison_table(stats, args.baseline)
    print(table)

    # Generate HTML report
    output_path = args.output or args.metrics_file.parent / 'comparison.html'
    generate_html_report(stats, metrics, output_path, args.baseline)
    print(f"\nHTML report written to: {output_path}")


if __name__ == '__main__':
    main()
