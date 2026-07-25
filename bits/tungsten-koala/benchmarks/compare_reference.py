"""Run Koala and scikit-learn on identical fixtures and compare metrics."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
BENCH = Path(__file__).resolve().parent
TOLERANCE = 1e-12


def metrics(command: list[str]) -> dict[str, float]:
    completed = subprocess.run(
        command,
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    out: dict[str, float] = {}
    for line in completed.stdout.splitlines():
        if "," in line:
            name, value = line.split(",", 1)
            out[name] = float(value)
    return out


koala = metrics(
    [
        str(ROOT / "bin" / "tungsten"),
        "run",
        str(BENCH / "reference_koala.w"),
    ]
)
sklearn = metrics([sys.executable, str(BENCH / "reference_sklearn.py")])

if koala.keys() != sklearn.keys():
    raise SystemExit(
        f"metric mismatch: koala={sorted(koala)} sklearn={sorted(sklearn)}"
    )

failed = False
print("metric,koala,sklearn,absolute_delta,status")
for name in koala:
    delta = abs(koala[name] - sklearn[name])
    status = "PASS" if delta <= TOLERANCE else "FAIL"
    failed = failed or status == "FAIL"
    print(
        f"{name},{koala[name]:.17g},{sklearn[name]:.17g},"
        f"{delta:.3g},{status}"
    )

if failed:
    raise SystemExit(1)
