#!/usr/bin/env python3
"""
Compare two DIA-NN pg_matrix.tsv files to assess quantitative agreement.

Compares protein group (PG) quantification results from two workflow runs
to determine whether parameter or model changes produce meaningful differences.

Usage:
    python bin/compare_pg_matrices.py matrix_a.tsv matrix_b.tsv [options]

Output:
    - Console summary with verdict (CONSISTENT / MINOR DIFFERENCES / SIGNIFICANT DIFFERENCES)
    - TSV metrics file for programmatic use

Metrics computed:
    1. PG counts and overlap
    2. Quantitative agreement (log2 ratios, Pearson r)
    3. Missingness disagreement
    4. Borderline PG characterization
    5. Per-sample completeness
    6. Systematic bias by intensity quartile
    7. Overall verdict
"""

import argparse
import math
import sys
from pathlib import Path

try:
    import duckdb
except ImportError:
    print("ERROR: duckdb is required. Install with: pip install duckdb", file=sys.stderr)
    sys.exit(1)

# Annotation columns in DIA-NN pg_matrix.tsv (everything else is a sample column)
ANNOTATION_COLS = {
    'Protein.Group', 'Protein.Ids', 'Protein.Names', 'Genes',
    'First.Protein.Description', 'N.Sequences', 'N.Proteotypic.Sequences'
}


def load_matrix(conn, path, table_name):
    """Load pg_matrix.tsv into DuckDB and return metadata.

    Returns dict with: n_pgs, n_samples, sample_cols, pg_set
    """
    conn.execute(
        f"CREATE TABLE {table_name} AS "
        f"SELECT * FROM read_csv_auto('{path}', delim='\\t', header=true, all_varchar=false)"
    )

    # Get column info
    cols = [row[0] for row in conn.execute(f"DESCRIBE {table_name}").fetchall()]
    sample_cols = [c for c in cols if c not in ANNOTATION_COLS]

    # Get PG set
    pgs = set(
        row[0] for row in conn.execute(
            f'SELECT DISTINCT "Protein.Group" FROM {table_name}'
        ).fetchall()
    )

    return {
        'n_pgs': len(pgs),
        'n_samples': len(sample_cols),
        'sample_cols': sample_cols,
        'pg_set': pgs
    }


def build_summary_table(conn, table_name, summary_name):
    """Create per-PG summary (mean intensity, n_quantified) using UNPIVOT.

    Dynamically handles any sample columns by excluding known annotation columns.
    """
    # Build the EXCLUDE list from columns that actually exist in the table
    actual_cols = [row[0] for row in conn.execute(f"DESCRIBE {table_name}").fetchall()]
    exclude_cols = [c for c in actual_cols if c in ANNOTATION_COLS]
    exclude_str = ', '.join(f'"{c}"' for c in exclude_cols)

    conn.execute(f"""
        CREATE TABLE {summary_name} AS
        SELECT
            "Protein.Group",
            AVG(value) FILTER (WHERE value > 0 AND value IS NOT NULL) AS mean_intensity,
            COUNT(value) FILTER (WHERE value > 0 AND value IS NOT NULL) AS n_quantified,
            COUNT(*) AS n_total
        FROM (
            UNPIVOT {table_name}
            ON COLUMNS(* EXCLUDE ({exclude_str}))
            INTO NAME sample VALUE value
        )
        GROUP BY "Protein.Group"
    """)


def compute_overlap(meta_a, meta_b):
    """Compute PG overlap statistics."""
    shared = meta_a['pg_set'] & meta_b['pg_set']
    unique_a = meta_a['pg_set'] - meta_b['pg_set']
    unique_b = meta_b['pg_set'] - meta_a['pg_set']
    union = meta_a['pg_set'] | meta_b['pg_set']
    overlap_pct = len(shared) / len(union) * 100 if union else 0

    return {
        'shared': len(shared),
        'unique_a': len(unique_a),
        'unique_b': len(unique_b),
        'overlap_pct': overlap_pct
    }


def compute_quantitative_agreement(conn):
    """Compute log2 ratio distribution and Pearson r on shared PGs."""
    result = conn.execute("""
        SELECT
            COUNT(*) AS n_compared,
            MEDIAN(log2_ratio) AS log2_ratio_median,
            AVG(log2_ratio) AS log2_ratio_mean,
            STDDEV(log2_ratio) AS log2_ratio_sd,
            CORR(log2_a, log2_b) AS pearson_r,
            COUNT(CASE WHEN ABS(log2_ratio) > 0.2 THEN 1 END) * 1.0 / COUNT(*) AS frac_gt_0_2,
            COUNT(CASE WHEN ABS(log2_ratio) > 0.5 THEN 1 END) * 1.0 / COUNT(*) AS frac_gt_0_5,
            COUNT(CASE WHEN ABS(log2_ratio) > 1.0 THEN 1 END) * 1.0 / COUNT(*) AS frac_gt_1_0
        FROM (
            SELECT
                LN(a.mean_intensity) / LN(2) AS log2_a,
                LN(b.mean_intensity) / LN(2) AS log2_b,
                LN(a.mean_intensity / b.mean_intensity) / LN(2) AS log2_ratio
            FROM summary_a a
            INNER JOIN summary_b b ON a."Protein.Group" = b."Protein.Group"
            WHERE a.mean_intensity > 0 AND b.mean_intensity > 0
        )
    """).fetchone()

    if result[0] == 0:
        return {k: None for k in [
            'n_compared', 'log2_ratio_median', 'log2_ratio_mean', 'log2_ratio_sd',
            'pearson_r', 'frac_gt_0_2', 'frac_gt_0_5', 'frac_gt_1_0'
        ]}

    return {
        'n_compared': result[0],
        'log2_ratio_median': result[1],
        'log2_ratio_mean': result[2],
        'log2_ratio_sd': result[3],
        'pearson_r': result[4],
        'frac_gt_0_2': result[5],
        'frac_gt_0_5': result[6],
        'frac_gt_1_0': result[7]
    }


def compute_missingness(conn):
    """Compute PGs quantified in one run but not the other."""
    result = conn.execute("""
        SELECT
            SUM(CASE WHEN a.n_quantified > 0 AND (b.n_quantified IS NULL OR b.n_quantified = 0)
                THEN 1 ELSE 0 END) AS pg_only_a,
            SUM(CASE WHEN b.n_quantified > 0 AND (a.n_quantified IS NULL OR a.n_quantified = 0)
                THEN 1 ELSE 0 END) AS pg_only_b,
            COUNT(*) AS total_pgs
        FROM summary_a a
        FULL OUTER JOIN summary_b b ON a."Protein.Group" = b."Protein.Group"
    """).fetchone()

    return {
        'pg_only_a': result[0] or 0,
        'pg_only_b': result[1] or 0,
        'total_pgs_union': result[2]
    }


def characterize_borderline_pgs(conn):
    """Characterize PGs unique to each run vs shared PGs.

    Returns intensity and quantification stats for unique vs shared PGs.
    """
    result = conn.execute("""
        WITH shared_stats AS (
            SELECT
                MEDIAN(a.mean_intensity) AS median_int,
                MEDIAN(a.n_quantified) AS median_nq
            FROM summary_a a
            INNER JOIN summary_b b ON a."Protein.Group" = b."Protein.Group"
            WHERE a.mean_intensity > 0
        ),
        unique_a AS (
            SELECT
                COUNT(*) AS n,
                MEDIAN(a.mean_intensity) AS median_int,
                MEDIAN(a.n_quantified) AS median_nq
            FROM summary_a a
            LEFT JOIN summary_b b ON a."Protein.Group" = b."Protein.Group"
            WHERE b."Protein.Group" IS NULL AND a.mean_intensity > 0
        ),
        unique_b AS (
            SELECT
                COUNT(*) AS n,
                MEDIAN(b.mean_intensity) AS median_int,
                MEDIAN(b.n_quantified) AS median_nq
            FROM summary_b b
            LEFT JOIN summary_a a ON b."Protein.Group" = a."Protein.Group"
            WHERE a."Protein.Group" IS NULL AND b.mean_intensity > 0
        )
        SELECT
            s.median_int, s.median_nq,
            ua.n, ua.median_int, ua.median_nq,
            ub.n, ub.median_int, ub.median_nq
        FROM shared_stats s, unique_a ua, unique_b ub
    """).fetchone()

    return {
        'shared_median_intensity': result[0],
        'shared_median_n_quantified': result[1],
        'unique_a_count': result[2] or 0,
        'unique_a_median_intensity': result[3],
        'unique_a_median_n_quantified': result[4],
        'unique_b_count': result[5] or 0,
        'unique_b_median_intensity': result[6],
        'unique_b_median_n_quantified': result[7],
    }


def compute_per_sample_completeness(conn, meta_a, meta_b):
    """Compare per-sample completeness when sample columns match between runs."""
    common_samples = sorted(set(meta_a['sample_cols']) & set(meta_b['sample_cols']))

    if not common_samples:
        return []

    results = []
    for sample in common_samples:
        row = conn.execute(f"""
            SELECT
                COUNT(CASE WHEN a."{sample}" > 0 AND a."{sample}" IS NOT NULL THEN 1 END) AS quant_a,
                COUNT(CASE WHEN b."{sample}" > 0 AND b."{sample}" IS NOT NULL THEN 1 END) AS quant_b
            FROM matrix_a a
            FULL OUTER JOIN matrix_b b ON a."Protein.Group" = b."Protein.Group"
        """).fetchone()
        results.append({
            'sample': sample,
            'quantified_a': row[0],
            'quantified_b': row[1]
        })

    return results


def compute_systematic_bias(conn):
    """Detect systematic bias by computing log2 ratio per intensity quartile."""
    rows = conn.execute("""
        WITH shared AS (
            SELECT
                a."Protein.Group",
                (a.mean_intensity + b.mean_intensity) / 2 AS avg_intensity,
                LN(a.mean_intensity / b.mean_intensity) / LN(2) AS log2_ratio
            FROM summary_a a
            INNER JOIN summary_b b ON a."Protein.Group" = b."Protein.Group"
            WHERE a.mean_intensity > 0 AND b.mean_intensity > 0
        ),
        quartiled AS (
            SELECT *, NTILE(4) OVER (ORDER BY avg_intensity) AS quartile
            FROM shared
        )
        SELECT
            quartile,
            COUNT(*) AS n,
            MEDIAN(log2_ratio) AS median_log2_ratio,
            STDDEV(log2_ratio) AS sd_log2_ratio
        FROM quartiled
        GROUP BY quartile
        ORDER BY quartile
    """).fetchall()

    return [
        {'quartile': r[0], 'n': r[1], 'median_log2_ratio': r[2], 'sd_log2_ratio': r[3]}
        for r in rows
    ]


def determine_verdict(overlap, quant):
    """Determine overall verdict based on metrics.

    Returns (verdict_string, reasons_list).
    """
    reasons = []
    is_significant = False
    is_minor = False

    # Overlap check
    op = overlap['overlap_pct']
    if op < 75:
        is_significant = True
        reasons.append("Low PG overlap: %.1f%%" % op)
    elif op < 90:
        is_minor = True
        reasons.append("Moderate PG overlap: %.1f%%" % op)

    # Correlation check
    r = quant.get('pearson_r')
    if r is not None:
        if r < 0.85:
            is_significant = True
            reasons.append("Low correlation: r=%.4f" % r)
        elif r < 0.95:
            is_minor = True
            reasons.append("Moderate correlation: r=%.4f" % r)

    # Systematic bias check
    median_ratio = abs(quant.get('log2_ratio_median') or 0)
    if median_ratio > 0.3:
        is_significant = True
        reasons.append("Large systematic shift: median log2 ratio=%.3f" % median_ratio)
    elif median_ratio > 0.1:
        is_minor = True
        reasons.append("Moderate systematic shift: median log2 ratio=%.3f" % median_ratio)

    # Large-difference fraction check
    frac_1 = quant.get('frac_gt_1_0') or 0
    if frac_1 > 0.15:
        is_significant = True
        reasons.append("High fraction with |log2 ratio| > 1.0: %.1f%%" % (frac_1 * 100))
    elif frac_1 > 0.05:
        is_minor = True
        reasons.append("Moderate fraction with |log2 ratio| > 1.0: %.1f%%" % (frac_1 * 100))

    if is_significant:
        return ("SIGNIFICANT DIFFERENCES", reasons)
    elif is_minor:
        return ("MINOR DIFFERENCES", reasons)
    else:
        return ("CONSISTENT", reasons if reasons else ["All metrics within expected ranges"])


def fmt(value, decimals=4):
    """Format a numeric value, returning 'NA' for None."""
    if value is None:
        return 'NA'
    if isinstance(value, int):
        return str(value)
    return f"{value:.{decimals}f}"


def fmt_pct(value):
    """Format a fraction as percentage string."""
    if value is None:
        return 'NA'
    return "%.1f%%" % (value * 100)


def print_report(label_a, label_b, meta_a, meta_b, overlap, quant,
                 missingness, borderline, per_sample, bias, verdict, reasons):
    """Print formatted console report."""
    print()
    print("=" * 70)
    print("  PG Matrix Comparison: %s vs %s" % (label_a, label_b))
    print("=" * 70)

    # PG Counts
    print("\n  PG Counts")
    print("  " + "-" * 40)
    print("    %s: %d PGs (%d samples)" % (label_a, meta_a['n_pgs'], meta_a['n_samples']))
    print("    %s: %d PGs (%d samples)" % (label_b, meta_b['n_pgs'], meta_b['n_samples']))

    # Overlap
    print("\n  PG Overlap")
    print("  " + "-" * 40)
    print("    Shared:          %d" % overlap['shared'])
    print("    Only in %s: %d" % (label_a.ljust(8), overlap['unique_a']))
    print("    Only in %s: %d" % (label_b.ljust(8), overlap['unique_b']))
    print("    Overlap:         %.1f%%" % overlap['overlap_pct'])

    # Quantitative Agreement
    print("\n  Quantitative Agreement (shared PGs, mean intensity per PG)")
    print("  " + "-" * 40)
    print("    PGs compared:        %s" % fmt(quant['n_compared'], 0))
    print("    Pearson r:           %s" % fmt(quant['pearson_r']))
    print("    Log2 ratio median:   %s" % fmt(quant['log2_ratio_median']))
    print("    Log2 ratio mean:     %s" % fmt(quant['log2_ratio_mean']))
    print("    Log2 ratio SD:       %s" % fmt(quant['log2_ratio_sd']))
    print("    |log2 ratio| > 0.2:  %s" % fmt_pct(quant['frac_gt_0_2']))
    print("    |log2 ratio| > 0.5:  %s" % fmt_pct(quant['frac_gt_0_5']))
    print("    |log2 ratio| > 1.0:  %s" % fmt_pct(quant['frac_gt_1_0']))

    # Missingness
    print("\n  Missingness Disagreement")
    print("  " + "-" * 40)
    print("    Quantified only in %s: %d" % (label_a, missingness['pg_only_a']))
    print("    Quantified only in %s: %d" % (label_b, missingness['pg_only_b']))

    # Borderline PGs
    if borderline['unique_a_count'] > 0 or borderline['unique_b_count'] > 0:
        print("\n  Borderline PG Characterization")
        print("  " + "-" * 40)
        print("    Shared PGs:    median intensity=%.0f, median samples quantified=%.0f" % (
            borderline['shared_median_intensity'] or 0,
            borderline['shared_median_n_quantified'] or 0))
        if borderline['unique_a_count'] > 0:
            print("    Unique %s: median intensity=%.0f, median samples quantified=%.0f  (%d PGs)" % (
                label_a,
                borderline['unique_a_median_intensity'] or 0,
                borderline['unique_a_median_n_quantified'] or 0,
                borderline['unique_a_count']))
        if borderline['unique_b_count'] > 0:
            print("    Unique %s: median intensity=%.0f, median samples quantified=%.0f  (%d PGs)" % (
                label_b,
                borderline['unique_b_median_intensity'] or 0,
                borderline['unique_b_median_n_quantified'] or 0,
                borderline['unique_b_count']))

    # Per-sample completeness
    if per_sample:
        print("\n  Per-Sample Completeness (quantified PGs)")
        print("  " + "-" * 40)
        n_show = min(len(per_sample), 8)
        for ps in per_sample[:n_show]:
            sname = ps['sample'].split('/')[-1][:30]
            print("    %-30s  %d / %d" % (sname, ps['quantified_a'], ps['quantified_b']))
        if len(per_sample) > n_show:
            print("    ... (%d more samples)" % (len(per_sample) - n_show))

    # Systematic bias
    if bias:
        print("\n  Systematic Bias (log2 ratio by intensity quartile)")
        print("  " + "-" * 40)
        for q in bias:
            print("    Q%d: median=%+.3f  SD=%.3f  (n=%d)" % (
                q['quartile'], q['median_log2_ratio'] or 0,
                q['sd_log2_ratio'] or 0, q['n']))

    # Verdict
    print()
    print("  " + "=" * 40)
    print("  VERDICT: %s" % verdict)
    for reason in reasons:
        print("    - %s" % reason)
    print("  " + "=" * 40)
    print()


def write_metrics_tsv(path, all_metrics):
    """Write all metrics to a flat TSV file (one metric per row)."""
    with open(path, 'w') as f:
        f.write("metric\tvalue\n")
        for key, value in all_metrics.items():
            if value is None:
                f.write("%s\tNA\n" % key)
            elif isinstance(value, float):
                f.write("%s\t%.6f\n" % (key, value))
            else:
                f.write("%s\t%s\n" % (key, value))


def main():
    parser = argparse.ArgumentParser(
        description='Compare two DIA-NN pg_matrix.tsv files (sanity pair comparison)'
    )
    parser.add_argument('matrix_a', type=Path, help='First pg_matrix.tsv file')
    parser.add_argument('matrix_b', type=Path, help='Second pg_matrix.tsv file')
    parser.add_argument('--label-a', type=str, default='A',
                        help='Label for first matrix (default: A)')
    parser.add_argument('--label-b', type=str, default='B',
                        help='Label for second matrix (default: B)')
    parser.add_argument('--output', '-o', type=Path, default=None,
                        help='Output TSV file (default: comparison_metrics.tsv)')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose output')

    args = parser.parse_args()

    # Validate inputs
    if not args.matrix_a.exists():
        print("ERROR: File not found: %s" % args.matrix_a, file=sys.stderr)
        sys.exit(1)
    if not args.matrix_b.exists():
        print("ERROR: File not found: %s" % args.matrix_b, file=sys.stderr)
        sys.exit(1)

    conn = duckdb.connect()

    # Load matrices
    if args.verbose:
        print("Loading %s ..." % args.matrix_a)
    meta_a = load_matrix(conn, args.matrix_a, 'matrix_a')

    if args.verbose:
        print("Loading %s ..." % args.matrix_b)
    meta_b = load_matrix(conn, args.matrix_b, 'matrix_b')

    # Build per-PG summary tables
    build_summary_table(conn, 'matrix_a', 'summary_a')
    build_summary_table(conn, 'matrix_b', 'summary_b')

    # Compute metrics
    overlap = compute_overlap(meta_a, meta_b)
    quant = compute_quantitative_agreement(conn)
    missingness = compute_missingness(conn)
    borderline = characterize_borderline_pgs(conn)
    per_sample = compute_per_sample_completeness(conn, meta_a, meta_b)
    bias = compute_systematic_bias(conn)
    verdict, reasons = determine_verdict(overlap, quant)

    # Print console report
    print_report(
        args.label_a, args.label_b, meta_a, meta_b,
        overlap, quant, missingness, borderline,
        per_sample, bias, verdict, reasons
    )

    # Write TSV metrics
    output_path = args.output or Path('comparison_metrics.tsv')
    all_metrics = {
        'label_a': args.label_a,
        'label_b': args.label_b,
        'pg_count_a': meta_a['n_pgs'],
        'pg_count_b': meta_b['n_pgs'],
        'n_samples_a': meta_a['n_samples'],
        'n_samples_b': meta_b['n_samples'],
        'overlap_shared': overlap['shared'],
        'overlap_unique_a': overlap['unique_a'],
        'overlap_unique_b': overlap['unique_b'],
        'overlap_pct': overlap['overlap_pct'],
        'quant_n_compared': quant['n_compared'],
        'quant_pearson_r': quant['pearson_r'],
        'quant_log2_ratio_median': quant['log2_ratio_median'],
        'quant_log2_ratio_mean': quant['log2_ratio_mean'],
        'quant_log2_ratio_sd': quant['log2_ratio_sd'],
        'quant_frac_gt_0_2': quant['frac_gt_0_2'],
        'quant_frac_gt_0_5': quant['frac_gt_0_5'],
        'quant_frac_gt_1_0': quant['frac_gt_1_0'],
        'miss_pg_only_a': missingness['pg_only_a'],
        'miss_pg_only_b': missingness['pg_only_b'],
        'borderline_shared_median_intensity': borderline['shared_median_intensity'],
        'borderline_unique_a_median_intensity': borderline['unique_a_median_intensity'],
        'borderline_unique_b_median_intensity': borderline['unique_b_median_intensity'],
        'verdict': verdict,
    }

    # Add bias quartiles
    for q in bias:
        all_metrics['bias_q%d_median_log2' % q['quartile']] = q['median_log2_ratio']
        all_metrics['bias_q%d_sd_log2' % q['quartile']] = q['sd_log2_ratio']

    write_metrics_tsv(output_path, all_metrics)
    print("Metrics written to: %s" % output_path)

    conn.close()


if __name__ == '__main__':
    main()
