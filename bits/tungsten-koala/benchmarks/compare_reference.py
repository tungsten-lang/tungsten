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
    # Koala clips probabilities at 1e-15; sklearn 1.9 clips at the f64
    # machine epsilon. The three identical confident misses therefore have
    # different finite raw-tree log losses by definition.
    "iris_tree_raw_log_loss": 0.12,
    # The implementations cross-fit the same tree folds; their Platt solver
    # and isotonic threshold pruning differ slightly but must land at the
    # same held-out calibration quality.
    "iris_tree_sigmoid_log_loss": 0.01,
    "iris_tree_isotonic_log_loss": 0.01,
    "iris_tree_isotonic_brier": 0.002,
}

# Beyond closeness to sklearn, calibration must actually solve the problem:
# each calibrated log loss must be below one fifth of the overconfident raw
# tree's, and isotonic Brier error must fall by at least five percent.
QUALITY_RATIOS = {
    "sigmoid_log_loss_vs_raw": (
        "iris_tree_sigmoid_log_loss",
        "iris_tree_raw_log_loss",
        0.20,
    ),
    "isotonic_log_loss_vs_raw": (
        "iris_tree_isotonic_log_loss",
        "iris_tree_raw_log_loss",
        0.20,
    ),
    "isotonic_brier_vs_raw": (
        "iris_tree_isotonic_brier",
        "iris_tree_raw_brier",
        0.95,
    ),
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

print("quality_gate,koala_ratio,sklearn_ratio,max_ratio,status")
for name, (calibrated_name, raw_name, max_ratio) in QUALITY_RATIOS.items():
    koala_ratio = koala[calibrated_name] / koala[raw_name]
    sklearn_ratio = sklearn[calibrated_name] / sklearn[raw_name]
    status = (
        "PASS"
        if koala_ratio <= max_ratio and sklearn_ratio <= max_ratio
        else "FAIL"
    )
    failed = failed or status == "FAIL"
    print(
        f"{name},{koala_ratio:.17g},{sklearn_ratio:.17g},"
        f"{max_ratio:.3g},{status}"
    )

if failed:
    raise SystemExit(1)
