#!/usr/bin/env python3
"""Analyze DIA-NN report and/or spectral library to find optimal library generation parameters.

Compares identified precursors (from report) against the predicted library search space
to find parameter ranges that maximize proteome coverage while minimizing library size.

Requires: pandas, pyarrow

Usage:
    # Analyze both report and library
    python analyze_library_params.py --report report.parquet --library library.parquet

    # Analyze report only
    python analyze_library_params.py --report report.parquet

    # Analyze library only
    python analyze_library_params.py --library library.parquet
"""

import argparse
import re
import sys

import pandas as pd


def analyze_distribution(series, name, percentiles=(0.5, 1, 2.5, 5, 95, 97.5, 99, 99.5)):
    """Print summary statistics and percentiles for a numeric distribution."""
    print(f"\n{'='*60}")
    print(f"  {name}")
    print(f"{'='*60}")
    print(f"  Count     : {len(series):,}")
    print(f"  Min       : {series.min():.2f}")
    print(f"  Max       : {series.max():.2f}")
    print(f"  Mean      : {series.mean():.2f}")
    print(f"  Median    : {series.median():.2f}")
    print(f"  Std       : {series.std():.2f}")
    print(f"\n  Percentiles:")
    for p in percentiles:
        val = series.quantile(p / 100)
        print(f"    {p:>5.1f}% : {val:.2f}")


def analyze_charge(series, name):
    """Print charge state distribution."""
    print(f"\n{'='*60}")
    print(f"  {name}")
    print(f"{'='*60}")
    vc = series.value_counts().sort_index()
    total = len(series)
    for charge, count in vc.items():
        pct = count / total * 100
        print(f"  Charge {int(charge):+d}: {count:>10,}  ({pct:5.1f}%)")


def analyze_peptide_length(series, name):
    """Print peptide length distribution. Returns lengths series."""
    lengths = series.str.len()
    print(f"\n{'='*60}")
    print(f"  {name}")
    print(f"{'='*60}")
    print(f"  Count     : {len(lengths):,}")
    print(f"  Min       : {lengths.min()}")
    print(f"  Max       : {lengths.max()}")
    print(f"  Mean      : {lengths.mean():.1f}")
    print(f"  Median    : {lengths.median():.0f}")
    print(f"\n  Length distribution:")
    vc = lengths.value_counts().sort_index()
    total = len(lengths)
    cumulative = 0
    for length, count in vc.items():
        cumulative += count
        pct = count / total * 100
        cum_pct = cumulative / total * 100
        bar = '#' * int(pct)
        print(f"    {int(length):>3d}: {count:>8,}  ({pct:5.1f}%, cum {cum_pct:5.1f}%) {bar}")
    return lengths


def find_column(df, candidates):
    """Find the first matching column name from a list of candidates."""
    for col in candidates:
        if col in df.columns:
            return col
    return None


def load_report(path):
    """Load and filter DIA-NN report to unique precursors at 1% FDR."""
    print(f"\nLoading report: {path}")
    report = pd.read_parquet(path)
    print(f"  Shape: {report.shape}")

    if 'Q.Value' in report.columns:
        confident = report[report['Q.Value'] <= 0.01]
        print(f"  Precursors at 1% FDR: {len(confident):,} / {len(report):,}")
    else:
        confident = report
        print(f"  No Q.Value column, using all {len(report):,} entries")

    if 'Precursor.Id' in report.columns:
        unique = confident.drop_duplicates(subset='Precursor.Id')
        print(f"  Unique precursors: {len(unique):,}")
    else:
        unique = confident

    return unique


def load_library(path):
    """Load spectral library parquet and deduplicate to unique precursors."""
    print(f"\nLoading library: {path}")
    lib = pd.read_parquet(path)
    print(f"  Shape: {lib.shape} (fragment-level rows)")

    id_col = find_column(lib, ['Precursor.Id', 'PrecursorId'])
    if id_col:
        unique = lib.drop_duplicates(subset=id_col)
        print(f"  Unique precursors: {len(unique):,}")
    else:
        unique = lib
        print(f"  WARNING: No precursor ID column found, using all rows")

    return lib, unique


def get_sequence_lengths(df):
    """Get peptide lengths from the best available sequence column."""
    seq_col = find_column(df, ['Stripped.Sequence', 'StrippedSequence'])
    if seq_col:
        return df[seq_col].str.len(), seq_col

    mod_col = find_column(df, ['Modified.Sequence', 'ModifiedSequence'])
    if mod_col:
        clean = df[mod_col].apply(lambda x: re.sub(r'\([^)]*\)', '', str(x)))
        return clean.str.len(), mod_col

    return None, None


def coverage_table(report_series, lib_series, ranges, label, fmt="d"):
    """Print a coverage vs search space table for a set of parameter ranges."""
    total_report = len(report_series) if report_series is not None else 0
    total_lib = len(lib_series)

    col_w = 7 if fmt == "d" else 7
    print(f"\n  {label} Range Analysis")
    print(f"  {'─'*50}")
    if report_series is not None:
        print(f"  Report range : {report_series.min():{'.1f' if fmt != 'd' else ''}} - {report_series.max():{'.1f' if fmt != 'd' else ''}}")
    print(f"  Library range: {lib_series.min():{'.1f' if fmt != 'd' else ''}} - {lib_series.max():{'.1f' if fmt != 'd' else ''}}")

    print(f"\n  {'Min':>7s} {'Max':>7s} | ", end="")
    if report_series is not None:
        print(f"{'Report Coverage':>16s} | ", end="")
    print(f"{'Library Entries':>16s} | {'Library Reduction':>18s}")

    print(f"  {'─'*7} {'─'*7} | ", end="")
    if report_series is not None:
        print(f"{'─'*16} | ", end="")
    print(f"{'─'*16} | {'─'*18}")

    for lo, hi in ranges:
        lib_in = ((lib_series >= lo) & (lib_series <= hi)).sum()
        lib_pct = lib_in / total_lib * 100
        lib_reduction = (1 - lib_in / total_lib) * 100

        if report_series is not None:
            report_in = ((report_series >= lo) & (report_series <= hi)).sum()
            report_pct = report_in / total_report * 100
            print(f"  {lo:>7.0f} {hi:>7.0f} | {report_in:>8,} ({report_pct:5.1f}%) | {lib_in:>8,} ({lib_pct:5.1f}%) | {lib_reduction:>16.1f}%")
        else:
            print(f"  {lo:>7.0f} {hi:>7.0f} | {lib_in:>8,} ({lib_pct:5.1f}%) | {lib_reduction:>16.1f}%")


def main():
    parser = argparse.ArgumentParser(
        description="Analyze DIA-NN report and/or library for optimal library generation parameters."
    )
    parser.add_argument("--report", help="Path to DIA-NN report parquet file")
    parser.add_argument("--library", help="Path to spectral library parquet file")
    args = parser.parse_args()

    if not args.report and not args.library:
        parser.error("At least one of --report or --library is required")

    report_unique = None
    report_mz = None
    report_charge = None
    report_lengths = None

    lib_full = None
    lib_unique = None
    lib_mz = None
    lib_charge = None
    lib_lengths = None

    # ── Report analysis ──────────────────────────────────────────
    if args.report:
        print("\n" + "#" * 70)
        print("#  REPORT ANALYSIS (Identified Precursors)")
        print("#" * 70)

        report_unique = load_report(args.report)

        mz_col = find_column(report_unique, ['Precursor.Mz', 'PrecursorMz'])
        if mz_col:
            report_mz = report_unique[mz_col]
            analyze_distribution(report_mz, f"REPORT - {mz_col} (unique, 1% FDR)")

        charge_col = find_column(report_unique, ['Precursor.Charge', 'PrecursorCharge'])
        if charge_col:
            report_charge = report_unique[charge_col]
            analyze_charge(report_charge, f"REPORT - {charge_col} (unique, 1% FDR)")

        report_lengths, seq_col = get_sequence_lengths(report_unique)
        if report_lengths is not None:
            analyze_peptide_length(
                report_unique[seq_col] if 'Stripped' in seq_col else report_unique[seq_col],
                f"REPORT - Peptide Length (unique, 1% FDR)"
            )

    # ── Library analysis ─────────────────────────────────────────
    if args.library:
        print("\n\n" + "#" * 70)
        print("#  LIBRARY ANALYSIS (Predicted Spectral Library)")
        print("#" * 70)

        lib_full, lib_unique = load_library(args.library)

        mz_col = find_column(lib_unique, ['Precursor.Mz', 'PrecursorMz'])
        if mz_col:
            lib_mz = lib_unique[mz_col]
            analyze_distribution(lib_mz, f"LIBRARY - {mz_col} (unique precursors)")

        charge_col = find_column(lib_unique, ['Precursor.Charge', 'PrecursorCharge'])
        if charge_col:
            lib_charge = lib_unique[charge_col]
            analyze_charge(lib_charge, f"LIBRARY - {charge_col} (unique precursors)")

        lib_lengths, seq_col = get_sequence_lengths(lib_unique)
        if lib_lengths is not None:
            analyze_peptide_length(
                lib_unique[seq_col],
                f"LIBRARY - Peptide Length (unique precursors)"
            )

    # ── Coverage optimization ────────────────────────────────────
    if lib_mz is not None:
        print("\n\n" + "#" * 70)
        print("#  COVERAGE vs. SEARCH SPACE OPTIMIZATION")
        print("#" * 70)

        # Precursor Mz ranges
        mz_ranges = [
            (300, 1800), (350, 1650), (350, 1400), (350, 1200), (400, 1200),
        ]
        if report_mz is not None:
            mz_ranges.append((report_mz.quantile(0.005), report_mz.quantile(0.995)))
            mz_ranges.append((report_mz.quantile(0.01), report_mz.quantile(0.99)))
        coverage_table(report_mz, lib_mz, mz_ranges, "Precursor.Mz")

        # Charge ranges
        if lib_charge is not None:
            charge_ranges = [(2, 3), (2, 4), (1, 4)]
            coverage_table(report_charge, lib_charge, charge_ranges, "Precursor.Charge")

        # Peptide length ranges
        if lib_lengths is not None:
            len_ranges = [(7, 30), (7, 25), (7, 20), (8, 25), (8, 20)]
            coverage_table(report_lengths, lib_lengths, len_ranges, "Peptide Length")

        # Combined scenario analysis
        if lib_charge is not None and lib_lengths is not None:
            print(f"\n\n{'='*60}")
            print(f"  Combined Parameter Optimization (Unique Precursors)")
            print(f"{'='*60}")

            scenarios = [
                ("Current (350-1350, z1-4, len 7-30)", 350, 1350, 1, 4, 7, 30),
                ("Conservative (350-1350, z2-4, len 7-25)", 350, 1350, 2, 4, 7, 25),
                ("Balanced (350-1200, z2-4, len 7-25)", 350, 1200, 2, 4, 7, 25),
                ("Aggressive (400-1200, z2-3, len 7-25)", 400, 1200, 2, 3, 7, 25),
                ("Max reduction (400-1200, z2-3, len 8-20)", 400, 1200, 2, 3, 8, 20),
            ]

            total = len(lib_unique)
            header = f"\n  {'Scenario':<45s} | {'Precursors':>12s} | {'Reduction':>10s}"
            if report_mz is not None:
                header += f" | {'Report Coverage':>16s}"
            print(header)
            sep = f"  {'─'*45} | {'─'*12} | {'─'*10}"
            if report_mz is not None:
                sep += f" | {'─'*16}"
            print(sep)

            for name, mz_lo, mz_hi, z_lo, z_hi, len_lo, len_hi in scenarios:
                mask = (
                    (lib_mz >= mz_lo) & (lib_mz <= mz_hi) &
                    (lib_charge >= z_lo) & (lib_charge <= z_hi) &
                    (lib_lengths >= len_lo) & (lib_lengths <= len_hi)
                )
                count = mask.sum()
                reduction = (1 - count / total) * 100
                line = f"  {name:<45s} | {count:>10,}  | {reduction:>8.1f}%"

                if report_mz is not None and report_charge is not None and report_lengths is not None:
                    r_mask = (
                        (report_mz >= mz_lo) & (report_mz <= mz_hi) &
                        (report_charge >= z_lo) & (report_charge <= z_hi) &
                        (report_lengths >= len_lo) & (report_lengths <= len_hi)
                    )
                    r_count = r_mask.sum()
                    r_pct = r_count / len(report_unique) * 100
                    line += f" | {r_count:>8,} ({r_pct:5.1f}%)"

                print(line)

    print()


if __name__ == "__main__":
    main()
