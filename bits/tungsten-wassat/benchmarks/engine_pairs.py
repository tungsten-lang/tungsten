#!/usr/bin/env python3
"""Interleave two release prop_bench binaries on fixed CDCL workloads.

The manifest is a JSON array of {name, path, conflicts, mode, env} records.
Only name/path are required; conflicts defaults to 20000, mode to raw.
Optional seconds/ticks set the benchmark's solve-time/million-tick limits.
Optional env contains explicit WASSAT_* interventions. Ambient WASSAT_*
settings are stripped. Timing is descriptive; correctness/proof checks must
run separately. Search-counter agreement distinguishes throughput changes
from changes to the trajectory. Every repetition is retained in --out.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import time


def digest(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--reps", type=int, default=5)
    parser.add_argument("--timeout", type=float, default=90)
    parser.add_argument("--baseline-env", action="append", default=[], metavar="WASSAT_NAME=VALUE")
    parser.add_argument("--candidate-env", action="append", default=[], metavar="WASSAT_NAME=VALUE")
    args = parser.parse_args()
    if args.reps < 1 or args.timeout <= 0:
        parser.error("reps and timeout must be positive")
    binaries = {name: getattr(args, name).resolve() for name in ("baseline", "candidate")}
    overrides = {}
    for name in binaries:
        overrides[name] = {}
        for value in getattr(args, name + "_env"):
            key, sep, val = value.partition("=")
            if not sep or not key.startswith("WASSAT_"):
                parser.error("interventions must be WASSAT_NAME=VALUE")
            overrides[name][key] = val
    cases = json.loads(args.manifest.read_text())
    names = set()
    for case in cases:
        if case["name"] in names:
            parser.error(f"duplicate case name: {case['name']}")
        names.add(case["name"])
        case["path"] = str(Path(case["path"]).expanduser().resolve())
        case["sha256"] = digest(case["path"])
        case.setdefault("mode", "raw")
        case.setdefault("conflicts", 20000)
        case.setdefault("seconds", 0)
        case.setdefault("ticks", 0)
        if (case["mode"] not in ("raw", "light", "heavy")
                or any(not isinstance(case[k], int) or case[k] < 0
                       for k in ("conflicts", "seconds", "ticks"))):
            parser.error(f"invalid mode or search limit: {case}")
        if any(not key.startswith("WASSAT_") for key in case.get("env", {})):
            parser.error("interventions must use WASSAT_* environment variables")
    report = {
        "binaries": {k: {"path": str(p), "sha256": digest(p)} for k, p in binaries.items()},
        "cases": cases, "overrides": overrides, "runs": [], "summary": [],
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)

    def save():
        args.out.write_text(json.dumps(report, indent=2) + "\n")

    environment = {k: v for k, v in os.environ.items() if not k.startswith("WASSAT_")}
    environment.update(TUNGSTEN_ALLOC_PROFILE="0", TUNGSTEN_POOL_STATS="0")
    search_fields = ("status", "conflicts", "decisions", "props", "ticks", "restarts", "reduces")
    for case in cases:
        records = []
        for rep in range(args.reps):
            pair = []
            order = ("baseline", "candidate") if rep % 2 == 0 else ("candidate", "baseline")
            for version in order:
                command = [str(binaries[version]), case["path"], str(case["conflicts"]),
                           str(case["seconds"]), case["mode"], str(case["ticks"])]
                started = time.monotonic()
                try:
                    result = subprocess.run(command, capture_output=True, text=True, timeout=args.timeout,
                                            env=environment | case.get("env", {}) | overrides[version])
                except subprocess.TimeoutExpired as error:
                    # Keep the failed trial in the evidence too. Python can
                    # return captured bytes on timeout even in text mode.
                    def decoded(value):
                        return value.decode(errors="replace") if isinstance(value, bytes) else value or ""
                    report["runs"].append({"case": case["name"], "version": version, "rep": rep,
                                           "wall_s": time.monotonic() - started, "rc": None,
                                           "timeout_s": args.timeout,
                                           "stdout": decoded(error.stdout), "stderr": decoded(error.stderr)})
                    save()
                    raise
                row = {"case": case["name"], "version": version, "rep": rep,
                       "wall_s": time.monotonic() - started, "rc": result.returncode,
                       "stdout": result.stdout, "stderr": result.stderr}
                report["runs"].append(row)
                save()
                lines = [line for line in result.stdout.splitlines() if line.startswith("RESULT ")]
                if result.returncode != 0 or len(lines) != 1:
                    raise RuntimeError(f"benchmark failed: {row}")
                values = dict(token.split("=", 1) for token in lines[0].split()[1:])
                row["counters"] = {k: int(v) if v.lstrip("-").isdigit() else v for k, v in values.items()}
                if row["counters"]["status"] not in (-1, 0, 1):
                    raise RuntimeError(f"invalid status: {row}")
                pair.append(row["counters"])
                records.append(row)
                save()
            if {p["status"] for p in pair} == {-1, 1}:
                raise RuntimeError(f"contradictory verdicts on {case['name']}")
        summary = {"case": case["name"]}
        for version in binaries:
            selected = [r["counters"] for r in records if r["version"] == version]
            summary[version + "_ms"] = statistics.median(r["solve_ms"] for r in selected)
            summary[version + "_statuses"] = sorted({r["status"] for r in selected})
        baseline = summary["baseline_ms"]
        summary["candidate_over_baseline"] = summary["candidate_ms"] / baseline if baseline else None
        # Include repetitions: nondeterminism also disqualifies a throughput-only claim.
        summary["same_search"] = len({tuple(r["counters"].get(k) for k in search_fields)
                                      for r in records}) == 1
        summary["all_solved"] = all(r["counters"]["status"] != 0 for r in records)
        report["summary"].append(summary)
        save()
        print(json.dumps(summary), flush=True)


if __name__ == "__main__":
    main()
