#!/usr/bin/env python3
"""Build a per-stratum precision/recall table from hap.py *.extended.csv files.

Outputs a plain CSV (for the README / database) and a MultiQC custom-content TSV.
Standard library only.
"""
import argparse
import csv
import math
import sys

TYPES = ("SNP", "INDEL")
TOLERANCE = 1e-4
FIELDS = [
    "caller", "type", "stratum", "truth_total", "truth_tp", "truth_fn",
    "query_tp", "query_fp", "recall", "recall_ci_low", "recall_ci_high",
    "precision", "precision_ci_low", "precision_ci_high", "f1",
]


def wilson(k, n, z=1.96):
    """95% Wilson score interval for k successes out of n. (None, None) if n == 0."""
    if n == 0:
        return None, None
    p = k / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return max(0.0, centre - half), min(1.0, centre + half)


def _int(value):
    return int(float(value)) if value not in ("", None) else 0


def _ratio(k, n):
    return k / n if n else None


def _check(ours, reported, label):
    """Fail if our metric disagrees with the value hap.py reported."""
    if ours is None or reported in ("", None):
        return
    if abs(ours - float(reported)) > TOLERANCE:
        raise ValueError(f"{label}: computed {ours:.6f}, hap.py reported {reported}")


def parse_extended(path, caller):
    rows = []
    with open(path, newline="") as fh:
        for r in csv.DictReader(fh):
            if r["Type"] not in TYPES:
                continue
            if (r["Subtype"], r["Filter"], r["Genotype"], r["QQ"]) != ("*", "PASS", "*", "*"):
                continue
            if r["Subset"].startswith("TS_"):
                continue
            t_tp, t_fn = _int(r["TRUTH.TP"]), _int(r["TRUTH.FN"])
            q_tp, q_fp = _int(r["QUERY.TP"]), _int(r["QUERY.FP"])
            recall = _ratio(t_tp, t_tp + t_fn)
            precision = _ratio(q_tp, q_tp + q_fp)
            label = f"{caller}/{r['Type']}/{r['Subset']}"
            _check(recall, r.get("METRIC.Recall"), label + " recall")
            _check(precision, r.get("METRIC.Precision"), label + " precision")
            f1 = (2 * precision * recall / (precision + recall)
                  if recall is not None and precision is not None and precision + recall > 0
                  else None)
            r_lo, r_hi = wilson(t_tp, t_tp + t_fn)
            p_lo, p_hi = wilson(q_tp, q_tp + q_fp)
            rows.append({
                "caller": caller, "type": r["Type"], "stratum": r["Subset"],
                "truth_total": t_tp + t_fn, "truth_tp": t_tp, "truth_fn": t_fn,
                "query_tp": q_tp, "query_fp": q_fp,
                "recall": recall, "recall_ci_low": r_lo, "recall_ci_high": r_hi,
                "precision": precision, "precision_ci_low": p_lo, "precision_ci_high": p_hi,
                "f1": f1,
            })
    if not rows:
        raise ValueError(f"No PASS summary rows found in {path}")
    return rows


def _fmt(value):
    if value is None:
        return "NA"
    return f"{value:.4f}" if isinstance(value, float) else str(value)


def write_csv(rows, path):
    with open(path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS)
        w.writeheader()
        for row in rows:
            w.writerow({k: _fmt(row[k]) for k in FIELDS})


def write_mqc(rows, path):
    header = [
        "# id: 'benchmark_stratified'",
        "# section_name: 'Benchmark by region (hap.py, PASS)'",
        "# description: 'Recall/precision per caller, variant type and GIAB stratification. "
        "CI = 95% Wilson interval; wide intervals mean few truth variants. NA = nothing to measure.'",
        "# plot_type: 'table'",
    ]
    cols = ["truth_total", "recall", "recall_ci_low", "recall_ci_high",
            "precision", "precision_ci_low", "precision_ci_high", "f1"]
    with open(path, "w") as fh:
        fh.write("\n".join(header) + "\n")
        fh.write("\t".join(["row"] + cols) + "\n")
        for row in rows:
            name = f"{row['caller']} | {row['type']} | {row['stratum']}"
            values = ["" if row[c] is None else _fmt(row[c]) for c in cols]
            fh.write("\t".join([name] + values) + "\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--extended", action="append", required=True, metavar="CALLER:PATH",
                    help="hap.py extended.csv, prefixed with the caller name")
    ap.add_argument("--out-prefix", default="benchmark_stratified")
    args = ap.parse_args(argv)
    rows = []
    for item in args.extended:
        caller, sep, path = item.partition(":")
        if not sep or not caller or not path:
            ap.error(f"--extended expects CALLER:PATH, got {item!r}")
        rows.extend(parse_extended(path, caller))
    rows.sort(key=lambda r: (r["type"], r["stratum"], r["caller"]))
    write_csv(rows, f"{args.out_prefix}.csv")
    write_mqc(rows, f"{args.out_prefix}_mqc.tsv")
    return 0


if __name__ == "__main__":
    sys.exit(main())
