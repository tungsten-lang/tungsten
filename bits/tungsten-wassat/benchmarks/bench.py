#!/usr/bin/env python3
"""Compare Wassat with installed SAT solvers and verify its proofs.

Generate the small bundled corpus first with ``gen_instances.py``. Paths can
be overridden with WASSAT, WRAT, CADICAL, CRYPTOMINISAT5, Z3, BENCH, and
TIMEOUT; unavailable comparison tools are reported as ``--`` rather than
being assumed to live in a developer scratch directory.
"""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import time


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
BENCH = Path(os.environ.get("BENCH", "/tmp/satbench"))
TIMEOUT = float(os.environ.get("TIMEOUT", "20"))


def executable(env_name: str, default: Path | str) -> str | None:
    requested = os.environ.get(env_name)
    candidate = requested or str(default)
    if "/" in candidate:
        return candidate if Path(candidate).is_file() else None
    return shutil.which(candidate)


WASSAT = executable("WASSAT", ROOT / "bin" / "wassat")
WRAT = executable("WRAT", REPO / "bits" / "tungsten-wrat" / "bin" / "wrat")
CADICAL = executable("CADICAL", "cadical")
CMS5 = executable("CRYPTOMINISAT5", "cryptominisat5")
Z3 = executable("Z3", "z3")


def run(command: list[str] | None, timeout: float = TIMEOUT) -> tuple[float | None, str]:
    """Return elapsed seconds and the SAT/checker verdict."""
    if command is None:
        return None, "--"
    started = time.perf_counter()
    try:
        process = subprocess.run(
            command, capture_output=True, text=True, timeout=timeout, check=False
        )
    except subprocess.TimeoutExpired:
        return None, "TO"
    elapsed = time.perf_counter() - started
    verdict = ""
    for line in process.stdout.splitlines():
        if line.startswith("s "):
            verdict = line[2:].strip()
    return elapsed, verdict or f"exit-{process.returncode}"


def timed(command: list[str] | None) -> str:
    elapsed, _ = run(command)
    if command is None:
        return "--"
    return "TO" if elapsed is None else f"{1000 * elapsed:.1f}"


def command(binary: str | None, *args: str) -> list[str] | None:
    return None if binary is None else [binary, *args]


if WASSAT is None:
    raise SystemExit(
        f"Wassat binary not found at {ROOT / 'bin' / 'wassat'}; compile it or set WASSAT"
    )
if not BENCH.is_dir():
    raise SystemExit(f"benchmark corpus not found at {BENCH}; run benchmarks/gen_instances.py")


instances = ["php32", "php43", "php54", "php65", "php76", "php87", "rand3_20", "rand3_40"]
solvers = [
    ("wassat", lambda cnf: command(WASSAT, str(cnf), "--fast")),
    ("cadical", lambda cnf: command(CADICAL, str(cnf))),
    ("cms5", lambda cnf: command(CMS5, str(cnf))),
    ("z3", lambda cnf: command(Z3, "-dimacs", str(cnf))),
]

failures = 0

print(f"== Solvers (wall milliseconds; timeout {TIMEOUT:g}s) ==")
print(f"{'instance':<12}" + "".join(f"{name:>11}" for name, _ in solvers) + "   agreement")
for name in instances:
    cnf = BENCH / f"{name}.cnf"
    cells: list[str] = []
    verdicts: list[str] = []
    wassat_verdict = ""
    for solver_name, make_command in solvers:
        cmd = make_command(cnf)
        elapsed, verdict = run(cmd)
        cells.append("--" if cmd is None else ("TO" if elapsed is None else f"{1000 * elapsed:.1f}"))
        if solver_name == "wassat":
            wassat_verdict = verdict
        if verdict not in ("--", "TO") and not verdict.startswith("exit-"):
            verdicts.append(verdict)
    # A missing Wassat verdict is a failure, never silent agreement: a broken
    # binary that prints nothing must not produce a green table.
    if wassat_verdict in ("SATISFIABLE", "UNSATISFIABLE", "UNKNOWN"):
        agreement = "OK" if len(set(verdicts)) <= 1 else "MISMATCH: " + "/".join(verdicts)
    else:
        agreement = f"NO WASSAT VERDICT ({wassat_verdict})"
    if not agreement.startswith("OK"):
        failures += 1
    print(f"{name:<12}" + "".join(f"{cell:>11}" for cell in cells) + f"   {agreement}")


if WRAT is not None:
    print("\n== Proof checking (fresh identical refutation) ==")
    print(f"{'instance':<12}{'hinted ms':>12}{'plain ms':>12}{'steps':>10}")
    for name in ["php32", "php43", "php54", "php65", "php76", "php87"]:
        cnf = BENCH / f"{name}.cnf"
        wrat = BENCH / f"{name}.wrat"
        drat = BENCH / f"{name}.drat"
        # Stale certificates from an earlier run must never be re-checked as
        # if freshly produced: remove them before generation and require the
        # solver to actually report UNSAT.
        wrat.unlink(missing_ok=True)
        drat.unlink(missing_ok=True)
        generated = subprocess.run(
            [WASSAT, str(cnf), "--proof", str(wrat), "--drat", str(drat)],
            capture_output=True,
            text=True,
            timeout=max(TIMEOUT, 120),
            check=False,
        )
        produced_unsat = "s UNSATISFIABLE" in generated.stdout
        if generated.returncode != 0 or not produced_unsat or not wrat.is_file() or not drat.is_file():
            print(f"{name:<12}{'generation failed':>24}")
            failures += 1
            continue
        steps = sum(1 for line in wrat.read_text().splitlines() if line and not line.startswith("wrat"))
        hinted_ms, hinted_verdict = run([WRAT, str(cnf), str(wrat)], timeout=max(TIMEOUT, 120))
        plain_ms, plain_verdict = run([WRAT, str(cnf), str(drat)], timeout=max(TIMEOUT, 120))
        # The row is meaningful only when the independent checker says
        # VERIFIED for both dialects.
        if hinted_verdict != "VERIFIED" or plain_verdict != "VERIFIED":
            print(f"{name:<12}NOT VERIFIED (hinted={hinted_verdict}, plain={plain_verdict})")
            failures += 1
            continue
        print(
            f"{name:<12}{1000 * hinted_ms:>12.1f}"
            f"{1000 * plain_ms:>12.1f}{steps:>10}"
        )
else:
    print("\nProof checking skipped: tungsten-wrat binary was not found.")
    failures += 1

if failures:
    raise SystemExit(f"FAIL: {failures} benchmark row(s) failed")
print("\nOK: all rows agreed and all fresh certificates verified")
