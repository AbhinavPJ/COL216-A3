#!/usr/bin/env python3
"""Fit repeat-sweep metrics to y = a + b*r and report intercept/slope/R^2.

Supports two input schemas:
1) starter/scripts/collect_metrics.sh CSV (old/new variants)
2) starter/data/repeat_sweep.csv legacy summary
"""

from __future__ import annotations

import argparse
import csv
import math
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


@dataclass
class FitResult:
    impl: str
    metric: str
    graph_kind: str
    scope: str
    cache_config: str
    graph_file: str
    n: str
    source: str
    points: int
    intercept: float
    slope: float
    r2: float


def to_float(value: str) -> Optional[float]:
    if value is None:
        return None
    text = value.strip()
    if not text:
        return None
    try:
        return float(text)
    except ValueError:
        return None


def linear_fit(xs: Sequence[float], ys: Sequence[float]) -> Tuple[float, float, float]:
    if len(xs) != len(ys) or len(xs) < 2:
        raise ValueError("Need at least 2 aligned points")

    n = len(xs)
    x_mean = sum(xs) / n
    y_mean = sum(ys) / n

    ss_xx = sum((x - x_mean) ** 2 for x in xs)
    if ss_xx == 0:
        raise ValueError("All x values are identical")

    ss_xy = sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, ys))
    slope = ss_xy / ss_xx
    intercept = y_mean - slope * x_mean

    ss_tot = sum((y - y_mean) ** 2 for y in ys)
    ss_res = sum((y - (intercept + slope * x)) ** 2 for x, y in zip(xs, ys))
    r2 = 1.0 if ss_tot == 0 else 1.0 - (ss_res / ss_tot)

    return intercept, slope, r2


def infer_schema(fieldnames: Sequence[str]) -> str:
    names = set(fieldnames)
    if "measurement" in names and "repeat" in names and "impl" in names:
        return "metrics"
    if "repeat" in names and "impl" in names and "time_total_ms_median" in names:
        return "legacy_repeat_sweep"
    raise ValueError("Unsupported CSV schema")


def parse_metrics_schema(
    rows: Iterable[Dict[str, str]],
    metrics: Sequence[str],
    measurement_filter: str,
    scope_filter: str,
) -> List[FitResult]:
    grouped: Dict[Tuple[str, str, str, str, str, str, str, str], List[Tuple[float, float]]] = defaultdict(list)

    for row in rows:
        measurement = (row.get("measurement") or "").strip()
        scope = (row.get("scope") or "").strip()

        if measurement_filter != "all" and measurement != measurement_filter:
            continue
        if scope_filter != "all" and scope != scope_filter:
            continue

        repeat = to_float(row.get("repeat", ""))
        if repeat is None:
            continue

        impl = (row.get("impl") or "").strip()
        graph_kind = (row.get("graph_kind") or "unknown").strip()
        graph_file = (row.get("graph_file") or "").strip()
        cache_config = (row.get("cache_config") or "").strip()
        n = (row.get("n") or "").strip()
        source = (row.get("source") or "").strip()

        for metric in metrics:
            y = to_float(row.get(metric, ""))
            if y is None:
                continue
            key = (impl, metric, graph_kind, scope, cache_config, graph_file, n, source)
            grouped[key].append((repeat, y))

    results: List[FitResult] = []
    for key, points in grouped.items():
        impl, metric, graph_kind, scope, cache_config, graph_file, n, source = key
        points_sorted = sorted(points, key=lambda p: p[0])
        xs = [p[0] for p in points_sorted]
        ys = [p[1] for p in points_sorted]

        if len(points_sorted) < 2 or len(set(xs)) < 2:
            continue

        try:
            intercept, slope, r2 = linear_fit(xs, ys)
        except ValueError:
            continue

        results.append(
            FitResult(
                impl=impl,
                metric=metric,
                graph_kind=graph_kind,
                scope=scope,
                cache_config=cache_config,
                graph_file=graph_file,
                n=n,
                source=source,
                points=len(points_sorted),
                intercept=intercept,
                slope=slope,
                r2=r2,
            )
        )

    return sorted(
        results,
        key=lambda r: (r.metric, r.graph_kind, r.scope, r.cache_config, r.graph_file, r.n, r.source, r.impl),
    )


def parse_legacy_repeat_sweep(rows: Iterable[Dict[str, str]]) -> List[FitResult]:
    grouped: Dict[str, List[Tuple[float, float]]] = defaultdict(list)

    for row in rows:
        repeat = to_float(row.get("repeat", ""))
        y = to_float(row.get("time_total_ms_median", ""))
        impl = (row.get("impl") or "").strip()
        if repeat is None or y is None or not impl:
            continue
        grouped[impl].append((repeat, y))

    results: List[FitResult] = []
    for impl, points in sorted(grouped.items()):
        points_sorted = sorted(points, key=lambda p: p[0])
        xs = [p[0] for p in points_sorted]
        ys = [p[1] for p in points_sorted]
        if len(points_sorted) < 2 or len(set(xs)) < 2:
            continue

        intercept, slope, r2 = linear_fit(xs, ys)
        results.append(
            FitResult(
                impl=impl,
                metric="time_total_ms_median",
                graph_kind="legacy",
                scope="repeat_sweep",
                cache_config="",
                graph_file="",
                n="",
                source="",
                points=len(points_sorted),
                intercept=intercept,
                slope=slope,
                r2=r2,
            )
        )

    return results


def pairwise_overhead_rows(fits: Sequence[FitResult]) -> List[Dict[str, str]]:
    by_group: Dict[Tuple[str, str, str, str, str, str, str], Dict[str, FitResult]] = defaultdict(dict)
    for fit in fits:
        g = (fit.metric, fit.graph_kind, fit.scope, fit.cache_config, fit.graph_file, fit.n, fit.source)
        by_group[g][fit.impl] = fit

    rows: List[Dict[str, str]] = []
    for g, impl_map in sorted(by_group.items()):
        if "pointer" not in impl_map or "csr" not in impl_map:
            continue
        p = impl_map["pointer"]
        c = impl_map["csr"]
        rows.append(
            {
                "metric": g[0],
                "graph_kind": g[1],
                "scope": g[2],
                "cache_config": g[3],
                "graph_file": g[4],
                "n": g[5],
                "source": g[6],
                "pointer_intercept": f"{p.intercept:.8f}",
                "csr_intercept": f"{c.intercept:.8f}",
                "intercept_delta_csr_minus_pointer": f"{(c.intercept - p.intercept):.8f}",
                "pointer_slope": f"{p.slope:.8f}",
                "csr_slope": f"{c.slope:.8f}",
                "slope_ratio_pointer_div_csr": f"{(p.slope / c.slope):.8f}" if c.slope != 0 else "nan",
            }
        )
    return rows


def write_fits_csv(path: Path, fits: Sequence[FitResult]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "impl",
                "metric",
                "graph_kind",
                "scope",
                "cache_config",
                "graph_file",
                "n",
                "source",
                "points",
                "intercept",
                "slope",
                "r2",
            ]
        )
        for fit in fits:
            writer.writerow(
                [
                    fit.impl,
                    fit.metric,
                    fit.graph_kind,
                    fit.scope,
                    fit.cache_config,
                    fit.graph_file,
                    fit.n,
                    fit.source,
                    fit.points,
                    f"{fit.intercept:.10f}",
                    f"{fit.slope:.10f}",
                    f"{fit.r2:.10f}",
                ]
            )


def write_pairs_csv(path: Path, rows: Sequence[Dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fieldnames = [
        "metric",
        "graph_kind",
        "scope",
        "cache_config",
        "graph_file",
        "n",
        "source",
        "pointer_intercept",
        "csr_intercept",
        "intercept_delta_csr_minus_pointer",
        "pointer_slope",
        "csr_slope",
        "slope_ratio_pointer_div_csr",
    ]
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def print_summary(fits: Sequence[FitResult], pair_rows: Sequence[Dict[str, str]]) -> None:
    print("Fitted groups:", len(fits))
    for fit in fits:
        print(
            f"{fit.metric:>20s} | {fit.impl:7s} | scope={fit.scope:18s} | "
            f"a={fit.intercept:.8f}, b={fit.slope:.8f}, R2={fit.r2:.6f}, n={fit.points}"
        )

    if pair_rows:
        print("\nPointer vs CSR intercept deltas (csr - pointer):")
        for row in pair_rows:
            print(
                f"{row['metric']:>20s} | scope={row['scope']:18s} | "
                f"delta_intercept={row['intercept_delta_csr_minus_pointer']} | "
                f"slope_ratio(pointer/csr)={row['slope_ratio_pointer_div_csr']}"
            )


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Analyze repeat-sweep metrics via linear fits")
    p.add_argument("--input", required=True, help="Input CSV path")
    p.add_argument(
        "--metrics",
        default="time_ms_avg,d1_misses_total,lld_misses_total",
        help="Comma-separated numeric metric columns to fit (metrics schema only)",
    )
    p.add_argument(
        "--measurement",
        default="all",
        choices=["all", "runtime", "cachegrind"],
        help="Filter by measurement type (metrics schema only)",
    )
    p.add_argument(
        "--scope",
        default="all",
        help="Filter by scope value (metrics schema only), e.g. repeat_sweep or repeat_sweep_cache",
    )
    p.add_argument(
        "--out-fits",
        default="",
        help="Optional output CSV for fit coefficients",
    )
    p.add_argument(
        "--out-pairs",
        default="",
        help="Optional output CSV for pointer-vs-csr paired deltas",
    )
    return p.parse_args()


def main() -> int:
    args = parse_args()
    input_path = Path(args.input)
    if not input_path.exists():
        raise FileNotFoundError(f"Input CSV not found: {input_path}")

    with input_path.open("r", newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if not reader.fieldnames:
            raise ValueError("CSV has no header")
        schema = infer_schema(reader.fieldnames)
        rows = list(reader)

    if schema == "legacy_repeat_sweep":
        fits = parse_legacy_repeat_sweep(rows)
    else:
        metrics = [m.strip() for m in args.metrics.split(",") if m.strip()]
        fits = parse_metrics_schema(rows, metrics, args.measurement, args.scope)

    pair_rows = pairwise_overhead_rows(fits)

    print_summary(fits, pair_rows)

    if args.out_fits:
        write_fits_csv(Path(args.out_fits), fits)
    if args.out_pairs:
        write_pairs_csv(Path(args.out_pairs), pair_rows)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
