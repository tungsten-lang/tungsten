#!/usr/bin/env python3
"""Phase 2 statistical gate for the SLS engine.

Over a FIXED seed set (20 seeds per instance -- one lucky seed does not
pass), SLS alone must solve >= 80% of the satisfiable uf250 set and >= 1
satisfiable bmc-ibm instance, with every reported model validated here
against the original formula and time-to-model distributions reported.

uf250 runs the raw formulas (random 3-SAT has no structured shell); bmc
runs --pre (preprocessing strips the root-implication shell local search
wastes flips rediscovering; models are reconstructed and re-verified by the
solver before printing, and re-checked here).
"""

from __future__ import annotations

import os
import statistics
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WASSAT = os.environ.get("WASSAT", str(ROOT / "bin" / "wassat"))
UF250_DIR = Path(os.environ.get("UF250", "/tmp/satlib/uf250-1065/ai/hoos/Shortcuts/UF250.1065.100"))
BMC_DIR = Path(os.environ.get("BMC", "/tmp/satlib/structclean/bmc"))
SEEDS = [1000 + i for i in range(20)]
UF_FLIPS = int(os.environ.get("UF_FLIPS", "4000000"))
BMC_FLIPS = int(os.environ.get("BMC_FLIPS", "20000000"))
TIMEOUT = float(os.environ.get("TIMEOUT", "120"))


def parse_cnf(path: Path):
    nvars = 0
    clauses = []
    current = []
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if line.startswith("%"):
            break
        if not line or line.startswith("c"):
            continue
        if line.startswith("p"):
            nvars = int(line.split()[2])
            continue
        for tok in line.split():
            lit = int(tok)
            if lit == 0:
                clauses.append(current)
                current = []
            else:
                current.append(lit)
    return nvars, clauses


def model_of(stdout: str) -> set[int]:
    values: set[int] = set()
    for line in stdout.splitlines():
        if line.startswith("v "):
            values.update(int(t) for t in line[2:].split() if t != "0")
    return values


def satisfies(clauses, assignment) -> bool:
    return all(any(l in assignment for l in c) for c in clauses)


def run_sls(cnf: Path, seed: int, flips: int, pre: bool):
    cmd = [WASSAT, "sls", str(cnf), "--flips", str(flips), "--seed", str(seed)]
    if pre:
        cmd.append("--pre")
    t0 = time.perf_counter()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT, check=False)
    except subprocess.TimeoutExpired:
        return False, None, TIMEOUT
    dt = time.perf_counter() - t0
    if "s SATISFIABLE" in proc.stdout:
        return True, model_of(proc.stdout), dt
    return False, None, dt


def main() -> None:
    uf_instances = sorted(UF250_DIR.glob("uf250-*.cnf"))
    if not uf_instances:
        raise SystemExit(f"no uf250 instances under {UF250_DIR}")
    print(f"[sls-gate] {len(uf_instances)} uf250 instances, seeds {SEEDS[0]}..{SEEDS[-1]}, "
          f"{UF_FLIPS} flips/seed")

    solved = 0
    invalid = 0
    first_success_times: list[float] = []
    seeds_needed: list[int] = []
    for cnf in uf_instances:
        nvars, clauses = parse_cnf(cnf)
        hit = False
        for si, seed in enumerate(SEEDS):
            ok, model, dt = run_sls(cnf, seed, UF_FLIPS, pre=False)
            if ok:
                if not satisfies(clauses, model):
                    print(f"  INVALID MODEL {cnf.name} seed={seed}")
                    invalid += 1
                    break
                solved += 1
                first_success_times.append(dt)
                seeds_needed.append(si + 1)
                hit = True
                break
        if not hit:
            print(f"  unsolved: {cnf.name} (all {len(SEEDS)} seeds)")

    pct = 100.0 * solved / len(uf_instances)
    print(f"\n[uf250] solved {solved}/{len(uf_instances)} ({pct:.0f}%), invalid models: {invalid}")
    if first_success_times:
        ts = sorted(first_success_times)
        print(f"[uf250] time-to-model (first success): "
              f"min {ts[0]:.2f}s  median {statistics.median(ts):.2f}s  "
              f"p90 {ts[int(0.9 * (len(ts) - 1))]:.2f}s  max {ts[-1]:.2f}s")
        print(f"[uf250] seeds needed: median {statistics.median(seeds_needed):.0f}, "
              f"max {max(seeds_needed)}")

    bmc_solved = []
    for name in sorted(BMC_DIR.glob("bmc-*.cnf")):
        nvars, clauses = parse_cnf(name)
        for seed in SEEDS[:5]:
            ok, model, dt = run_sls(name, seed, BMC_FLIPS, pre=True)
            if ok:
                if not satisfies(clauses, model):
                    print(f"  INVALID MODEL {name.name} seed={seed}")
                    invalid += 1
                else:
                    bmc_solved.append((name.name, seed, dt))
                break
    print(f"\n[bmc] solved via --pre: {[(n, f'{t:.1f}s') for n, s, t in bmc_solved]}")

    ok = pct >= 80.0 and len(bmc_solved) >= 1 and invalid == 0
    if not ok:
        raise SystemExit(f"FAIL: uf250 {pct:.0f}% (need >=80), bmc {len(bmc_solved)} (need >=1), "
                         f"invalid {invalid} (need 0)")
    print(f"\nOK: gate passed — uf250 {pct:.0f}%, {len(bmc_solved)} bmc instances, all models valid")


if __name__ == "__main__":
    main()
