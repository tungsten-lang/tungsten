#!/usr/bin/env python3
"""Collect and compare Tungsten primitive benchmarks for CI.

The GitHub workflow measures the base revision and candidate on the same VM.
Committed baselines add a longer-lived signal, but are accepted only when the
recorded runner identity matches the current runner exactly.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import statistics
import subprocess
import sys
import tempfile
from pathlib import Path


SCHEMA = "tungsten-performance-v1"
DEFAULT_METRICS = (
    "int_add",
    "int_mul",
    "int_bitops",
    "float_mul",
    "new_array",
    "new_string",
    "str_concat",
    "new_object",
    "new_hash",
    "array_get",
    "array_get_heap",
    "array_mod",
    "array_set",
    "array_set_heap",
    "hash_get",
    "str_build",
    "fn_call",
    "method_call",
    "block_call",
)
IDENTITY_KEYS = ("runner_class", "os", "arch", "cpu_model", "logical_cpus")


class PerformanceError(RuntimeError):
    pass


def cpu_model() -> str:
    if sys.platform == "darwin":
        result = subprocess.run(
            ["sysctl", "-n", "machdep.cpu.brand_string"],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.strip()

    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.exists():
        for line in cpuinfo.read_text(errors="replace").splitlines():
            key, separator, value = line.partition(":")
            if separator and key.strip().lower() in {"model name", "processor"}:
                if value.strip():
                    return value.strip()
    return platform.processor() or "unknown"


def runner_identity(runner_class: str) -> dict[str, object]:
    return {
        "runner_class": runner_class,
        "os": platform.system(),
        "os_release": platform.release(),
        "arch": platform.machine(),
        "cpu_model": cpu_model(),
        "logical_cpus": os.cpu_count() or 0,
    }


def git_value(repo: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def read_tsv(path: Path, expected: tuple[str, ...]) -> dict[str, int]:
    values: dict[str, int] = {}
    for line in path.read_text().splitlines():
        name, separator, raw_value = line.partition("\t")
        if not separator or not name or not raw_value.isdigit():
            raise PerformanceError(f"malformed benchmark row in {path}: {line!r}")
        if name in values:
            raise PerformanceError(f"duplicate benchmark metric {name!r} in {path}")
        values[name] = int(raw_value)

    missing = [name for name in expected if name not in values]
    unexpected = sorted(set(values) - set(expected))
    if missing or unexpected:
        raise PerformanceError(
            f"benchmark metric drift: missing={missing or 'none'}, "
            f"unexpected={unexpected or 'none'}"
        )
    return values


def collect(args: argparse.Namespace) -> int:
    repo = args.repo.resolve()
    tungsten = repo / "bin" / "tungsten"
    if not tungsten.exists():
        raise PerformanceError(f"missing Tungsten launcher: {tungsten}")
    if args.samples < 2:
        raise PerformanceError("at least two measured samples are required")

    metrics = tuple(args.metrics or DEFAULT_METRICS)
    samples: dict[str, list[int]] = {name: [] for name in metrics}
    with tempfile.TemporaryDirectory(prefix="tungsten-performance-") as temp:
        temp_root = Path(temp)
        for index in range(args.samples):
            sample_dir = temp_root / f"sample-{index + 1}"
            sample_dir.mkdir()
            command = [
                str(tungsten),
                "bench",
                "--baseline",
                "--runs",
                str(args.runs),
                *metrics,
            ]
            print(
                f"performance sample {index + 1}/{args.samples}: "
                f"{len(metrics)} metrics",
                flush=True,
            )
            result = subprocess.run(
                command,
                cwd=sample_dir,
                env=os.environ.copy(),
                text=True,
            )
            if result.returncode != 0:
                raise PerformanceError(
                    f"benchmark sample {index + 1} exited {result.returncode}"
                )
            path = sample_dir / "bench_baseline.txt"
            if not path.exists():
                raise PerformanceError(f"benchmark did not write {path}")
            values = read_tsv(path, metrics)
            for name in metrics:
                samples[name].append(values[name])

    measured: dict[str, object] = {}
    for name in metrics:
        values = samples[name]
        median = int(statistics.median(values))
        deviations = [abs(value - median) for value in values]
        mad = int(statistics.median(deviations))
        observed_noise = (3.0 * mad / median) if median else 1.0
        measured[name] = {
            "unit": "ops_per_second",
            "samples": values,
            "median": median,
            "mad": mad,
            "noise_fraction": round(max(args.noise_floor, observed_noise), 6),
        }

    payload = {
        "schema": SCHEMA,
        "revision": git_value(repo, "rev-parse", "HEAD"),
        "source_date": git_value(repo, "show", "-s", "--format=%cI", "HEAD"),
        "runner": runner_identity(args.runner_class),
        "method": {
            "warmup_seconds_per_sample": 3,
            "samples": args.samples,
            "best_of_runs_per_sample": args.runs,
            "compile_profile": "--release --native --fast",
            "noise_floor_fraction": args.noise_floor,
        },
        "metrics": measured,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    print(f"wrote {args.output}")
    return 0


def load_result(path: Path) -> dict[str, object]:
    try:
        payload = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise PerformanceError(f"cannot read performance result {path}: {error}") from error
    if payload.get("schema") != SCHEMA:
        raise PerformanceError(f"unsupported performance schema in {path}")
    if not isinstance(payload.get("runner"), dict) or not isinstance(
        payload.get("metrics"), dict
    ):
        raise PerformanceError(f"incomplete performance result {path}")
    return payload


def identity_mismatches(
    baseline: dict[str, object], candidate: dict[str, object]
) -> list[str]:
    baseline_runner = baseline["runner"]
    candidate_runner = candidate["runner"]
    assert isinstance(baseline_runner, dict)
    assert isinstance(candidate_runner, dict)
    return [
        f"{key}: {baseline_runner.get(key)!r} != {candidate_runner.get(key)!r}"
        for key in IDENTITY_KEYS
        if baseline_runner.get(key) != candidate_runner.get(key)
    ]


def append_summary(lines: list[str], path: Path | None) -> None:
    text = "\n".join(lines) + "\n"
    print(text, end="")
    if path is not None:
        with path.open("a") as output:
            output.write(text)


def compare(args: argparse.Namespace) -> int:
    if not args.baseline.exists():
        if args.allow_missing:
            append_summary(
                [
                    "### Tungsten long-term performance baseline",
                    "",
                    f"No baseline exists at `{args.baseline}`; same-run base comparison still applies.",
                ],
                args.summary,
            )
            return 0
        raise PerformanceError(f"performance baseline does not exist: {args.baseline}")

    baseline = load_result(args.baseline)
    candidate = load_result(args.candidate)
    mismatches = identity_mismatches(baseline, candidate)
    if mismatches:
        lines = [
            "### Tungsten performance comparison refused",
            "",
            "Runner identities differ; update or select a matching baseline.",
            "",
            *[f"- {mismatch}" for mismatch in mismatches],
        ]
        append_summary(lines, args.summary)
        return 2

    baseline_metrics = baseline["metrics"]
    candidate_metrics = candidate["metrics"]
    assert isinstance(baseline_metrics, dict)
    assert isinstance(candidate_metrics, dict)
    if set(baseline_metrics) != set(candidate_metrics):
        raise PerformanceError(
            "metric sets differ: "
            f"baseline={sorted(baseline_metrics)}, candidate={sorted(candidate_metrics)}"
        )

    failures: list[str] = []
    rows = [
        "### Tungsten performance comparison",
        "",
        "| metric | baseline | candidate | delta | allowed regression | result |",
        "| --- | ---: | ---: | ---: | ---: | :---: |",
    ]
    for name in sorted(baseline_metrics):
        base_metric = baseline_metrics[name]
        current_metric = candidate_metrics[name]
        if not isinstance(base_metric, dict) or not isinstance(current_metric, dict):
            raise PerformanceError(f"malformed metric {name}")
        baseline_median = int(base_metric.get("median", 0))
        candidate_median = int(current_metric.get("median", 0))
        band = max(args.noise_floor, float(base_metric.get("noise_fraction", 0.0)))
        if baseline_median <= 0 or candidate_median <= 0:
            raise PerformanceError(f"non-positive median for {name}")
        if band > args.max_noise:
            raise PerformanceError(
                f"baseline {name} noise band {band:.1%} exceeds {args.max_noise:.1%}"
            )
        ratio = candidate_median / baseline_median
        passed = ratio >= (1.0 - band)
        result = "pass" if passed else "REGRESSION"
        if not passed:
            failures.append(name)
        rows.append(
            f"| {name} | {baseline_median:,} | {candidate_median:,} | "
            f"{ratio - 1.0:+.1%} | {band:.1%} | {result} |"
        )

    rows.extend(
        [
            "",
            f"Runner: `{candidate['runner']['runner_class']}` / "
            f"`{candidate['runner']['cpu_model']}`.",
        ]
    )
    append_summary(rows, args.summary)
    return 1 if failures else 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)

    measure = commands.add_parser("measure", help="collect benchmark samples")
    measure.add_argument("--repo", type=Path, required=True)
    measure.add_argument("--output", type=Path, required=True)
    measure.add_argument("--runner-class", required=True)
    measure.add_argument("--samples", type=int, default=3)
    measure.add_argument("--runs", type=int, default=1)
    measure.add_argument("--noise-floor", type=float, default=0.10)
    measure.add_argument("metrics", nargs="*")
    measure.set_defaults(handler=collect)

    comparison = commands.add_parser("compare", help="compare two JSON results")
    comparison.add_argument("--baseline", type=Path, required=True)
    comparison.add_argument("--candidate", type=Path, required=True)
    comparison.add_argument("--summary", type=Path)
    comparison.add_argument("--noise-floor", type=float, default=0.10)
    comparison.add_argument("--max-noise", type=float, default=0.25)
    comparison.add_argument("--allow-missing", action="store_true")
    comparison.set_defaults(handler=compare)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        return args.handler(args)
    except PerformanceError as error:
        print(f"performance-ci: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
