#!/usr/bin/env python3
"""
compare_runs.py

Compare diann-wf runs across multiple config YAML files.
Output directories are read from the 'outdir' field in each YAML.

Usage (from project root):
    compare_runs.py                                      # all YAMLs in config/diann-wf/
    compare_runs.py 'hfx--mouse-sample-*.yaml'           # glob relative to config/diann-wf/
    compare_runs.py config/diann-wf/a.yaml config/diann-wf/b.yaml  # explicit paths

Sections printed:
    - Config parameter comparison
    - Execution time by step (minutes)
    - Total task time per run (hours)
    - ID metrics by run / biospecimen / pass (median per sample)
    - Wide precursor / protein comparison per pass
"""

import re
import sys
import glob as _glob
from pathlib import Path

try:
    import pandas as pd
    import yaml
except ImportError as e:
    print(f"ERROR: {e}. Install with: pip install pandas pyyaml", file=sys.stderr)
    sys.exit(1)

pd.set_option("display.max_columns", None)
pd.set_option("display.width", 0)
pd.set_option("display.float_format", lambda x: f"{x:.3g}")

CONFIG_PARAMS = [
    "run", "diann_version", "model_preset", "individual_mass_acc",
    "smart_profiling", "qvalue", "mass_acc_cal", "mass_acc_ms1",
    "mass_acc", "pg_level", "threads", "parallel_mode",
]


# ── Helpers ────────────────────────────────────────────────────────────────────

def parse_nf_duration(x):
    """Parse a Nextflow duration string (e.g. '1h 23m 4.5s') into seconds."""
    if not x or (isinstance(x, float) and pd.isna(x)):
        return 0.0
    x = str(x).strip()
    h = re.search(r"(\d+)h", x)
    m = re.search(r"(\d+)m", x)
    s = re.search(r"([0-9.]+)s", x)
    return (int(h.group(1)) if h else 0) * 3600 + \
           (int(m.group(1)) if m else 0) * 60 + \
           (float(s.group(1)) if s else 0.0)


def parse_mem_gb(x):
    """Parse a Nextflow memory string (e.g. '1.5 GB', '500 MB') into GB."""
    if not x or (isinstance(x, float) and pd.isna(x)):
        return float("nan")
    x = str(x).strip()
    val = re.search(r"[0-9.]+", x)
    unit = re.search(r"[A-Z]+", x)
    if not val:
        return float("nan")
    v = float(val.group())
    u = unit.group() if unit else ""
    if u == "GB":
        return v
    elif u == "MB":
        return v / 1024
    elif u == "KB":
        return v / 1024 ** 2
    return v


def parse_task_name(name):
    """Extract (step, biospe) from a Nextflow task name.

    E.g. 'QUANTIFY_FASTA_SUBSET:QUANTIFY (plasma/batch1)' → ('QUANTIFY', 'plasma')
         'QUANTIFY_FASTA_SUBSET:GENERATE_LIBRARY'          → ('GENERATE_LIBRARY', None)
    """
    step_m = re.search(r":([A-Z_]+)", str(name))
    biospe_m = re.search(r"\(([a-z]+)/", str(name))
    return (
        step_m.group(1) if step_m else None,
        biospe_m.group(1) if biospe_m else None,
    )


# ── Config loading ─────────────────────────────────────────────────────────────

def read_config(yaml_path: Path, cwd: Path) -> dict:
    """Read a diann-wf config YAML and resolve the output directory."""
    with open(yaml_path) as f:
        cfg = yaml.safe_load(f)

    outdir_rel = cfg.get("outdir")
    outdir = None
    if outdir_rel:
        # Research projects store results in data/quant/<basename(outdir)>
        candidate = cwd / "data" / "quant" / Path(outdir_rel).name
        if candidate.is_dir():
            outdir = candidate
        else:
            candidate2 = cwd / outdir_rel
            if candidate2.is_dir():
                outdir = candidate2

    run = Path(outdir_rel).name if outdir_rel else yaml_path.stem

    return {
        "run": run,
        "outdir": outdir,
        "diann_version": cfg.get("diann_version"),
        "model_preset": cfg.get("model_preset"),
        "individual_mass_acc": bool(cfg.get("individual_mass_acc", False)),
        "smart_profiling": bool(cfg.get("smart_profiling", False)),
        "qvalue": cfg.get("qvalue"),
        "mass_acc_cal": cfg.get("mass_acc_cal"),
        "mass_acc_ms1": cfg.get("mass_acc_ms1"),
        "mass_acc": cfg.get("mass_acc"),
        "pg_level": cfg.get("pg_level"),
        "threads": cfg.get("threads"),
        "parallel_mode": bool(cfg.get("parallel_mode", False)),
    }


# ── Data loading ───────────────────────────────────────────────────────────────

def read_trace(run: str, outdir: Path) -> "pd.DataFrame | None":
    """Read the Nextflow execution trace for a run."""
    trace_file = outdir / "pipeline_info" / "execution_trace.txt"
    if not trace_file.exists():
        print(f"WARNING: No execution_trace.txt for {run}", file=sys.stderr)
        return None

    df = pd.read_csv(trace_file, sep="\t", dtype=str)
    steps, biospes = zip(*[parse_task_name(n) for n in df["name"]])
    df["step"] = steps
    df["biospe"] = biospes
    df["run"] = run
    df["duration_s"] = df["duration"].apply(parse_nf_duration)
    df["realtime_s"] = df["realtime"].apply(parse_nf_duration)
    df["cpu_pct"] = pd.to_numeric(df["%cpu"].str.rstrip("%"), errors="coerce")
    df["peak_rss_gb"] = df["peak_rss"].apply(parse_mem_gb)
    df["peak_vmem_gb"] = df["peak_vmem"].apply(parse_mem_gb)
    return df


def read_stats(run: str, outdir: Path) -> "pd.DataFrame | None":
    """Find and read all report.stats.tsv files under an output directory.

    Detects both flat (quant_full/<batch>/) and biospe-stratified
    (<biospe>/quant_full/<batch>/) directory structures.
    """
    stats_files = sorted(outdir.rglob("report.stats.tsv"))
    if not stats_files:
        print(f"WARNING: No report.stats.tsv found for {run}", file=sys.stderr)
        return None

    dfs = []
    for f in stats_files:
        parts = f.relative_to(outdir).parts
        # parts[0] starts with 'quant_' → flat structure (no biospe subdir)
        if parts[0].startswith("quant_"):
            biospe = "all"
            pass_ = parts[0].removeprefix("quant_")
        else:
            biospe = parts[0]
            pass_ = parts[1].removeprefix("quant_") if len(parts) > 2 else ""

        df = pd.read_csv(f, sep="\t")
        df["run"] = run
        df["biospe"] = biospe
        df["pass"] = pass_
        dfs.append(df)

    return pd.concat(dfs, ignore_index=True)


# ── CLI ────────────────────────────────────────────────────────────────────────

def resolve_config_files(args: list[str], cwd: Path) -> list[Path]:
    """Resolve CLI arguments to a list of YAML config paths."""
    config_root = cwd / "config" / "diann-wf"

    if not args:
        search_root = config_root if config_root.is_dir() else cwd
        files = sorted(search_root.glob("*.yaml"))
        if not files:
            print(f"ERROR: No .yaml files found in {search_root}", file=sys.stderr)
            sys.exit(1)
        return files

    files = []
    for a in args:
        p = Path(a)
        if p.exists():
            files.append(p.resolve())
        else:
            # Try glob relative to config_root then cwd
            hits = sorted(config_root.glob(a)) + sorted(cwd.glob(a))
            if not hits:
                print(f"WARNING: No files matched: {a}", file=sys.stderr)
            files.extend(hits)

    seen = set()
    return [f for f in files if not (f in seen or seen.add(f))]


# ── Printing helpers ───────────────────────────────────────────────────────────

def fmt(df: pd.DataFrame) -> str:
    return df.to_string(index=False)


def section(title: str, df: pd.DataFrame):
    print(f"\n=== {title} ===")
    print(fmt(df))


# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    import argparse

    parser = argparse.ArgumentParser(
        description="Compare diann-wf runs across config YAML files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "configs", nargs="*",
        help="YAML config files or globs (default: all YAMLs in config/diann-wf/)",
    )
    args = parser.parse_args()

    cwd = Path.cwd()
    config_files = resolve_config_files(args.configs, cwd)

    if not config_files:
        print("ERROR: No config YAML files found.", file=sys.stderr)
        sys.exit(1)

    print(f"Comparing {len(config_files)} config(s):")
    for f in config_files:
        print(f"  {f.name}")

    # ── Load configs ──────────────────────────────────────────────────────────
    configs = [read_config(f, cwd) for f in config_files]
    configs_df = pd.DataFrame(configs)

    missing = configs_df[configs_df["outdir"].isna() | ~configs_df["outdir"].apply(
        lambda p: p.is_dir() if p else False)]
    if not missing.empty:
        print(f"WARNING: outdir missing or not found for: {', '.join(missing['run'])}", file=sys.stderr)

    configs_ok = configs_df[configs_df["outdir"].notna() & configs_df["outdir"].apply(
        lambda p: p.is_dir() if p else False)].copy()

    if configs_ok.empty:
        print("ERROR: No accessible output directories found.", file=sys.stderr)
        sys.exit(1)

    # ── Config parameter comparison ───────────────────────────────────────────
    section("CONFIG PARAMETER COMPARISON",
            configs_df[CONFIG_PARAMS].sort_values("run"))

    # ── Execution traces ──────────────────────────────────────────────────────
    trace_frames = [
        read_trace(row["run"], row["outdir"])
        for _, row in configs_ok.iterrows()
    ]
    trace_frames = [t for t in trace_frames if t is not None]

    if trace_frames:
        traces = pd.merge(
            pd.concat(trace_frames, ignore_index=True),
            configs_ok[["run", "individual_mass_acc", "smart_profiling"]],
            on="run",
        )

        timing = (
            traces[traces["step"].notna()]
            .groupby(["run", "step", "individual_mass_acc", "smart_profiling"])
            .agg(
                n_tasks=("duration_s", "count"),
                total_min=("duration_s", lambda x: x.sum() / 60),
                mean_min=("duration_s", lambda x: x.mean() / 60),
                peak_rss_gb=("peak_rss_gb", "max"),
            )
            .reset_index()
            .sort_values(["step", "run"])
        )
        section("EXECUTION TIME BY STEP (minutes)", timing)

        total_time = (
            traces.groupby(["run", "individual_mass_acc", "smart_profiling"])
            .agg(total_h=("duration_s", lambda x: x.sum() / 3600), n_tasks=("duration_s", "count"))
            .reset_index()
        )
        section("TOTAL TASK TIME PER RUN (hours)", total_time)
    else:
        print("\n(No execution traces found — skipping timing summaries)")

    # ── Identification metrics ─────────────────────────────────────────────────
    stats_frames = [
        read_stats(row["run"], row["outdir"])
        for _, row in configs_ok.iterrows()
    ]
    stats_frames = [s for s in stats_frames if s is not None]

    if stats_frames:
        stats = pd.merge(
            pd.concat(stats_frames, ignore_index=True),
            configs_ok[["run", "individual_mass_acc", "smart_profiling"]],
            on="run",
        )

        id_summary = (
            stats.groupby(["run", "biospe", "pass", "individual_mass_acc", "smart_profiling"])
            .agg(
                n_samples=("Precursors.Identified", "count"),
                med_precursors=("Precursors.Identified", "median"),
                med_proteins=("Proteins.Identified", "median"),
                med_ms1_acc=("Median.Mass.Acc.MS1.Corrected", "median"),
                med_ms2_acc=("Median.Mass.Acc.MS2.Corrected", "median"),
                med_fwhm_rt=("FWHM.RT", "median"),
            )
            .reset_index()
            .sort_values(["biospe", "pass", "run"])
        )
        section("ID METRICS BY RUN / BIOSPECIMEN / PASS (median per sample)", id_summary)

        for pass_ in sorted(stats["pass"].unique()):
            subset = stats[stats["pass"] == pass_]

            for metric, label in [
                ("Precursors.Identified", "PRECURSORS"),
                ("Proteins.Identified", "PROTEINS"),
            ]:
                wide = (
                    subset.groupby(["run", "biospe"])[metric]
                    .median()
                    .reset_index()
                    .pivot(index="biospe", columns="run", values=metric)
                    .reset_index()
                )
                wide.columns.name = None
                section(f"{label}: run comparison (wide, pass = {pass_})", wide)
    else:
        print("\n(No report.stats.tsv files found — skipping ID metric summaries)")


if __name__ == "__main__":
    main()
