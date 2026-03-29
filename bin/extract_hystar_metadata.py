#!/usr/bin/env python3
"""
Extract Bruker HyStar acquisition metadata from TimsTOF .d directories.

Reads sample/batch definitions from a DIA-NN workflow YAML and for each entry
with file_type == 'd', finds all .d directories and extracts acquisition metadata
from HyStarMetadata.xml inside each Bruker TimsTOF .d folder.

Supported YAML structures:
    samples:   [{id, dir, file_type, recursive}]       # quantify_only, presearch_and_quantify
    batches:   [{id, dir, file_type, recursive}]       # quantify_fasta_subset
    biospecimens: [{id, batches: [{id, dir, ...}]}]    # quantify_fasta_subset_by_biospe

Usage:
    extract_hystar_metadata.py params.yaml [options]

Output CSV columns:
    YamlSampleId     - Sample/batch id from the YAML params file
    YamlBiospeId     - Biospecimen id (only for biospecimens YAML; empty otherwise)
    SampleID         - SampleID attribute from HyStarMetadata.xml
    CreationDateTime - Acquisition timestamp (ISO 8601, from HyStarMetadata.xml)
    FileName         - .d directory name only (no path)
    WindowsPath      - Full Windows path from HyStarMetadata.xml
    LocalPath        - Absolute local path to the .d directory

Examples:
    # Standalone - output goes to outdir defined in YAML
    extract_hystar_metadata.py configs/quantify/hela.yaml

    # Override output directory
    extract_hystar_metadata.py configs/quantify/hela.yaml --outdir results/hela

    # Custom output filename
    extract_hystar_metadata.py configs/quantify/hela.yaml --output run_metadata.csv

    # Nextflow integration (called from a work dir, paths resolved from launchDir)
    extract_hystar_metadata.py params.yaml --basedir /path/to/launchdir --output sample_metadata.csv
"""

import argparse
import csv
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML is required. Install with: pip install pyyaml", file=sys.stderr)
    sys.exit(1)


def find_d_dirs(base_dir: Path, recursive: bool) -> list:
    """Return sorted list of .d directories under base_dir."""
    if recursive:
        return sorted(p for p in base_dir.rglob("*.d") if p.is_dir())
    else:
        return sorted(p for p in base_dir.glob("*.d") if p.is_dir())


def parse_hystar_metadata(d_dir: Path) -> dict:
    """
    Parse HyStarMetadata.xml inside a .d directory.

    Returns dict with keys: CreationDateTime, SampleID, FileName, WindowsPath.
    Returns None if the file is missing or unparseable.
    """
    xml_path = d_dir / "HyStarMetadata.xml"
    if not xml_path.exists():
        return None

    try:
        root = ET.parse(xml_path).getroot()
    except ET.ParseError as exc:
        print(f"WARNING: Failed to parse {xml_path}: {exc}", file=sys.stderr)
        return None

    # AnalysisHeader may be a direct child or nested
    elem = root.find("AnalysisHeader")
    if elem is None:
        elem = root.find(".//AnalysisHeader")
    if elem is None:
        print(f"WARNING: No <AnalysisHeader> in {xml_path}", file=sys.stderr)
        return None

    windows_path = elem.get("FileName", "")
    # Extract basename from Windows backslash path
    file_name = windows_path.replace("\\", "/").split("/")[-1] if windows_path else d_dir.name

    return {
        "CreationDateTime": elem.get("CreationDateTime", ""),
        "SampleID": elem.get("SampleID", ""),
        "FileName": file_name,
        "WindowsPath": windows_path,
    }


def flatten_samples(params: dict) -> list:
    """
    Return a flat list of sample/batch entries from any supported YAML structure.

    Each entry is a dict with keys: id, dir, file_type, recursive, biospe_id.
    biospe_id is empty string for non-biospecimen YAMLs.
    """
    if "biospecimens" in params:
        result = []
        for biospe in params.get("biospecimens", []):
            biospe_id = biospe.get("id", "")
            for batch in biospe.get("batches", []):
                result.append({**batch, "biospe_id": biospe_id})
        return result
    elif "batches" in params:
        return [{**b, "biospe_id": ""} for b in params.get("batches", [])]
    else:
        return [{**s, "biospe_id": ""} for s in params.get("samples", [])]


def extract_metadata(params_file: Path, basedir: Path, outdir: Path, output_name: str) -> Path:
    with open(params_file) as fh:
        params = yaml.safe_load(fh)

    samples = flatten_samples(params)
    if not samples:
        print("WARNING: No sample/batch entries found in params file (checked 'samples', 'batches', 'biospecimens').", file=sys.stderr)

    resolved_outdir = outdir or Path(params.get("outdir", "."))

    rows = []
    for sample in samples:
        if sample.get("file_type", "") != "d":
            continue

        yaml_id = sample.get("id", "")
        biospe_id = sample.get("biospe_id", "")
        sample_dir_str = sample.get("dir", "")
        recursive = sample.get("recursive", False)

        sample_dir = Path(sample_dir_str)
        if not sample_dir.is_absolute():
            sample_dir = basedir / sample_dir

        if not sample_dir.exists():
            print(f"WARNING: Sample dir not found, skipping: {sample_dir}", file=sys.stderr)
            continue

        d_dirs = find_d_dirs(sample_dir, recursive)
        if not d_dirs:
            print(f"WARNING: No .d directories found in: {sample_dir}", file=sys.stderr)

        for d_dir in d_dirs:
            meta = parse_hystar_metadata(d_dir)
            if meta is None:
                print(f"WARNING: Skipping {d_dir.name} (no valid HyStarMetadata.xml)", file=sys.stderr)
                continue

            rows.append({
                "YamlSampleId": yaml_id,
                "YamlBiospeId": biospe_id,
                "SampleID": meta["SampleID"],
                "CreationDateTime": meta["CreationDateTime"],
                "FileName": meta["FileName"],
                "WindowsPath": meta["WindowsPath"],
                "LocalPath": str(d_dir.resolve()),
            })

    rows.sort(key=lambda r: r["CreationDateTime"])

    resolved_outdir.mkdir(parents=True, exist_ok=True)
    output_path = resolved_outdir / output_name

    fieldnames = ["YamlSampleId", "YamlBiospeId", "SampleID", "CreationDateTime", "FileName", "WindowsPath", "LocalPath"]
    with open(output_path, "w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Written {len(rows)} rows to: {output_path}")
    return output_path


def main():
    parser = argparse.ArgumentParser(
        description="Extract Bruker HyStarMetadata from .d dirs listed in a DIA-NN YAML params file.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split("Usage:")[1].split("Examples:")[1].strip(),
    )
    parser.add_argument("params_yaml", help="Path to DIA-NN workflow YAML params file")
    parser.add_argument(
        "--outdir",
        help="Output directory (default: outdir from YAML)",
    )
    parser.add_argument(
        "--basedir",
        help="Base directory for resolving relative 'dir' paths from the YAML "
             "(default: current working directory). Set to launchDir when called from Nextflow.",
    )
    parser.add_argument(
        "--output",
        default="sample_metadata.csv",
        metavar="FILENAME",
        help="Output CSV filename (default: sample_metadata.csv)",
    )

    args = parser.parse_args()

    params_file = Path(args.params_yaml)
    if not params_file.exists():
        print(f"ERROR: Params file not found: {params_file}", file=sys.stderr)
        sys.exit(1)

    basedir = Path(args.basedir).resolve() if args.basedir else Path.cwd()
    outdir = Path(args.outdir) if args.outdir else None

    extract_metadata(params_file, basedir, outdir, args.output)


if __name__ == "__main__":
    main()
