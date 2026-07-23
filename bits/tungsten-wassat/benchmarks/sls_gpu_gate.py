#!/usr/bin/env python3
"""E3 differential gate: the GPU walker fleet vs the CPU oracle.

The two engines run different algorithms by design (CPU: CCAnr with
configuration checking + clause weighting; GPU: independent WalkSAT/SKC
walkers), so trajectories are never compared — only capability and model
validity:

  1. uf250 sample: the GPU engine must solve every sampled instance the
     CPU engine solves (random 3-SAT is WalkSAT's home turf).
  2. bmc kernels via --pre: the GPU engine must solve >= 2 of the kernels
     the CPU gate solved. Kernels where plain WalkSAT plateaus without
     clause weighting (measured: bmc-ibm-5 at best_unsat=1 across 1024
     walkers x 20M flips) are a documented limitation, not a failure.
  3. Every model from either engine must validate against the ORIGINAL
     formula here, independently of the solver's own guard.
"""

from __future__ import annotations

import os
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WASSAT = os.environ.get("WASSAT", str(ROOT / "bin" / "wassat"))
UF250_DIR = Path(os.environ.get("UF250", "/tmp/satlib/uf250-1065/ai/hoos/Shortcuts/UF250.1065.100"))
BMC_DIR = Path(os.environ.get("BMC", "/tmp/satlib/structclean/bmc"))
UF_SAMPLE = int(os.environ.get("UF_SAMPLE", "20"))
SEED = int(os.environ.get("SEED", "1001"))
TIMEOUT = float(os.environ.get("TIMEOUT", "300"))

BMC_CPU_SOLVED = ["bmc-ibm-1.cnf", "bmc-ibm-2.cnf", "bmc-ibm-5.cnf", "bmc-ibm-7.cnf"]


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


def run(cnf: Path, gpu: bool, flips: int, pre: bool, noise: int = 48):
    cmd = [WASSAT, "sls", str(cnf), "--flips", str(flips), "--seed", str(SEED)]
    if gpu:
        cmd += ["--gpu", "--walkers", "512", "--noise", str(noise)]
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
    uf = sorted(UF250_DIR.glob("uf250-*.cnf"))[:UF_SAMPLE]
    if not uf:
        raise SystemExit(f"no uf250 instances under {UF250_DIR}")
    failures = 0
    invalid = 0

    print(f"[gpu-gate] uf250 sample n={len(uf)}, seed={SEED}")
    for cnf in uf:
        nvars, clauses = parse_cnf(cnf)
        cpu_ok, cpu_model, cpu_dt = run(cnf, gpu=False, flips=4000000, pre=False)
        gpu_ok, gpu_model, gpu_dt = run(cnf, gpu=True, flips=2000000, pre=False, noise=145)
        for tag, ok, model in (("cpu", cpu_ok, cpu_model), ("gpu", gpu_ok, gpu_model)):
            if ok and not satisfies(clauses, model):
                print(f"  INVALID {tag} MODEL on {cnf.name}")
                invalid += 1
        if cpu_ok and not gpu_ok:
            print(f"  GPU MISSED {cnf.name} (cpu {cpu_dt:.2f}s)")
            failures += 1
        else:
            print(f"  {cnf.name}: cpu {cpu_dt:.2f}s  gpu {gpu_dt:.2f}s")

    print(f"\n[gpu-gate] bmc kernels via --pre (CPU-solved set)")
    gpu_bmc = 0
    for name in BMC_CPU_SOLVED:
        cnf = BMC_DIR / name
        if not cnf.exists():
            continue
        nvars, clauses = parse_cnf(cnf)
        ok, model, dt = run(cnf, gpu=True, flips=8000000, pre=True)
        if ok:
            if satisfies(clauses, model):
                gpu_bmc += 1
                print(f"  {name}: solved {dt:.1f}s")
            else:
                print(f"  INVALID gpu MODEL on {name}")
                invalid += 1
        else:
            print(f"  {name}: not solved (documented WalkSAT plateau is acceptable)")

    ok = failures == 0 and invalid == 0 and gpu_bmc >= 2
    if not ok:
        raise SystemExit(f"FAIL: uf misses={failures} invalid={invalid} bmc={gpu_bmc} (need >=2)")
    print(f"\nOK: gpu matched cpu on all {len(uf)} uf250 samples, {gpu_bmc} bmc kernels, all models valid")


if __name__ == "__main__":
    main()
