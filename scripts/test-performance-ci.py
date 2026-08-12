#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "performance-ci.py"
RUNNER = {
    "runner_class": "blacksmith-4vcpu-ubuntu-2404",
    "os": "Linux",
    "os_release": "fixture",
    "arch": "x86_64",
    "cpu_model": "fixture cpu",
    "logical_cpus": 4,
}


def payload(median: int, *, noise: float = 0.10, runner: dict | None = None) -> dict:
    return {
        "schema": "tungsten-performance-v1",
        "revision": "fixture",
        "runner": runner or RUNNER,
        "metrics": {
            "int_add": {
                "unit": "ops_per_second",
                "samples": [median, median],
                "median": median,
                "mad": 0,
                "noise_fraction": noise,
            }
        },
    }


def compare(directory: Path, baseline: dict, candidate: dict, *extra: str) -> int:
    baseline_path = directory / "baseline.json"
    candidate_path = directory / "candidate.json"
    baseline_path.write_text(json.dumps(baseline))
    candidate_path.write_text(json.dumps(candidate))
    return subprocess.run(
        [
            str(SCRIPT),
            "compare",
            "--baseline",
            str(baseline_path),
            "--candidate",
            str(candidate_path),
            *extra,
        ],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode


with tempfile.TemporaryDirectory(prefix="tungsten-performance-contract-") as temp:
    directory = Path(temp)
    assert compare(directory, payload(100), payload(91)) == 0
    assert compare(directory, payload(100), payload(89)) == 1
    assert compare(directory, payload(100, noise=0.26), payload(100)) == 2

    other_runner = dict(RUNNER)
    other_runner["cpu_model"] = "different cpu"
    assert compare(directory, payload(100), payload(100, runner=other_runner)) == 2

    missing = directory / "missing.json"
    candidate = directory / "candidate.json"
    candidate.write_text(json.dumps(payload(100)))
    optional = subprocess.run(
        [
            str(SCRIPT),
            "compare",
            "--baseline",
            str(missing),
            "--candidate",
            str(candidate),
            "--allow-missing",
        ],
        check=False,
        stdout=subprocess.DEVNULL,
    )
    assert optional.returncode == 0

print("performance CI comparison contract: ok")
