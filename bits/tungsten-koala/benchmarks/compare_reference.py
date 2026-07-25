"""Run Koala and scikit-learn on identical fixtures and compare metrics."""

from __future__ import annotations

import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
BENCH = Path(__file__).resolve().parent
TOLERANCE = 1e-12
METRIC_TOLERANCES = {
    # GaussianNB differs by one of the 60 Iris rows under the two
    # implementations' numeric conventions. This gate is a held-out quality
    # comparison, not a claim of coefficient identity.
    "iris_gaussian_nb_cv_mean": 0.02,
}


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


with tempfile.TemporaryDirectory(prefix="koala-reference-") as temp_dir:
    executable = Path(temp_dir) / "reference-koala"
    subprocess.run(
        [
            str(ROOT / "bin" / "tungsten"),
            "compile",
            str(BENCH / "reference_koala.w"),
            "--out",
            str(executable),
        ],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    )
    koala = metrics([str(executable)])
sklearn = metrics([sys.executable, str(BENCH / "reference_sklearn.py")])

if koala.keys() != sklearn.keys():
    raise SystemExit(
        f"metric mismatch: koala={sorted(koala)} sklearn={sorted(sklearn)}"
    )

failed = False
print("metric,koala,sklearn,absolute_delta,tolerance,status")
for name in koala:
    delta = abs(koala[name] - sklearn[name])
    tolerance = METRIC_TOLERANCES.get(name, TOLERANCE)
    status = "PASS" if delta <= tolerance else "FAIL"
    failed = failed or status == "FAIL"
    print(
        f"{name},{koala[name]:.17g},{sklearn[name]:.17g},"
        f"{delta:.3g},{tolerance:.3g},{status}"
    )

if failed:
    raise SystemExit(1)
