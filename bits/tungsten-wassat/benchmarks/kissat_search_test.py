#!/usr/bin/env python3
"""Differential and certificate test for the Kissat search profile.

Every case runs with the profile forced onto every arm and its schedule
compressed (WASSAT_KSTRESS), so a search of a few thousand conflicts switches
modes, reduces its clause database above the root and vivifies many times.
Three contracts are checked against CaDiCaL's verdict:

  --fast               the threaded race
  --fast --sequential  the same pipeline on one core
  --drat               the certificate path, proof checked by tungsten-wrat

Satisfiable answers must come with a model of the original clauses.
"""

from __future__ import annotations

import os
from pathlib import Path
import random
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
WASSAT = os.environ.get("WASSAT", str(ROOT / "bin" / "wassat"))
WRAT = os.environ.get("WRAT", str(REPO / "bits" / "tungsten-wrat" / "bin" / "wrat"))
CADICAL = os.environ.get("CADICAL", shutil.which("cadical") or "")
CASES = int(os.environ.get("CASES", "60"))
SEED = int(os.environ.get("SEED", "20261115"))
TIMEOUT = float(os.environ.get("TIMEOUT", "300"))

FORCED = {
    "WASSAT_KSEARCH": "1",
    "WASSAT_KSTRESS": "50",
    "WASSAT_INPROCESS": "150",
    "WASSAT_BACKDOOR_TABLES": "0",
}


def verdict(output: str) -> str:
    for line in output.splitlines():
        if line.startswith("s "):
            return line[2:].strip()
    return ""


def model(output: str) -> set[int]:
    values: set[int] = set()
    for line in output.splitlines():
        if line.startswith("v "):
            values.update(int(token) for token in line[2:].split() if token != "0")
    return values


def satisfies(clauses: list[list[int]], assignment: set[int]) -> bool:
    return all(any(literal in assignment for literal in clause) for clause in clauses)


def random_3sat(rng: random.Random) -> tuple[int, list[list[int]]]:
    nvars = rng.randint(90, 150)
    count = int(nvars * rng.uniform(4.1, 4.4))
    clauses = []
    for _ in range(count):
        variables = rng.sample(range(1, nvars + 1), 3)
        clauses.append([v if rng.getrandbits(1) else -v for v in variables])
    return nvars, clauses


def pigeonhole(rng: random.Random) -> tuple[int, list[list[int]]]:
    holes = rng.randint(6, 8)
    pigeons = holes + rng.randint(0, 1)
    nvars = pigeons * holes
    names = list(range(1, nvars + 1))
    rng.shuffle(names)

    def variable(pigeon: int, hole: int) -> int:
        return names[pigeon * holes + hole]

    clauses = [[variable(p, h) for h in range(holes)] for p in range(pigeons)]
    for hole in range(holes):
        for left in range(pigeons):
            for right in range(left + 1, pigeons):
                clauses.append([-variable(left, hole), -variable(right, hole)])
    return nvars, clauses


def parity_chain(rng: random.Random) -> tuple[int, list[list[int]]]:
    """Two XOR chains over the same inputs, with equal or opposite targets."""
    width = rng.randint(14, 22)
    nvars = width
    clauses: list[list[int]] = []

    def xor3(a: int, b: int, c: int) -> None:
        # c = a xor b
        clauses.extend([[-a, -b, -c], [a, b, -c], [a, -b, c], [-a, b, c]])

    def chain(order: list[int]) -> int:
        nonlocal nvars
        acc = order[0]
        for x in order[1:]:
            nvars += 1
            xor3(acc, x, nvars)
            acc = nvars
        return acc

    inputs = list(range(1, width + 1))
    first = chain(inputs)
    shuffled = inputs[:]
    rng.shuffle(shuffled)
    second = chain(shuffled)
    if rng.getrandbits(1):
        clauses.extend([[first], [-second]])
    else:
        clauses.extend([[first], [second]])
    return nvars, clauses


def run(arguments: list[str], extra: dict[str, str] | None = None) -> subprocess.CompletedProcess:
    env = {k: v for k, v in os.environ.items() if not k.startswith("WASSAT_")}
    env.update(FORCED)
    env.update(extra or {})
    return subprocess.run(
        [WASSAT] + arguments, capture_output=True, text=True, timeout=TIMEOUT, check=False, env=env
    )


def main() -> None:
    if not Path(WASSAT).is_file():
        raise SystemExit(f"Wassat binary not found: {WASSAT}")
    if not Path(WRAT).is_file():
        raise SystemExit(f"tungsten-wrat binary not found: {WRAT}; certificate checking is mandatory")
    if not CADICAL:
        raise SystemExit("CaDiCaL not found; set CADICAL to run this test")
    rng = random.Random(SEED)
    makers = [random_3sat, random_3sat, pigeonhole, parity_chain]
    sat = unsat = proofs = 0
    with tempfile.TemporaryDirectory(prefix="wassat-kissat-search-") as directory:
        root = Path(directory)
        for case in range(CASES):
            nvars, clauses = makers[case % len(makers)](rng)
            cnf = root / f"case-{case:04d}.cnf"
            cnf.write_text(
                f"p cnf {nvars} {len(clauses)}\n"
                + "".join(" ".join(map(str, clause)) + " 0\n" for clause in clauses)
            )
            reference = subprocess.run(
                [CADICAL, str(cnf)], capture_output=True, text=True, timeout=TIMEOUT, check=False
            )
            expected = verdict(reference.stdout)
            if expected not in ("SATISFIABLE", "UNSATISFIABLE"):
                raise SystemExit(f"CaDiCaL gave no verdict on {cnf}")
            for label, arguments in (
                ("--fast", [str(cnf), "--fast"]),
                ("--fast --sequential", [str(cnf), "--fast", "--sequential"]),
            ):
                ours = run(arguments)
                got = verdict(ours.stdout)
                if got != expected:
                    shutil.copy(cnf, Path(tempfile.gettempdir()) / cnf.name)
                    raise SystemExit(
                        f"verdict mismatch under {label} on case {case} "
                        f"(kept as {Path(tempfile.gettempdir()) / cnf.name}): "
                        f"Wassat={got or ours.stderr[-200:]}, CaDiCaL={expected}"
                    )
                if got == "SATISFIABLE" and not satisfies(clauses, model(ours.stdout)):
                    raise SystemExit(f"invalid model under {label} on case {case}")
            proof = root / f"case-{case:04d}.drat"
            produced = run([str(cnf), "--drat", str(proof)])
            got = verdict(produced.stdout)
            if got != expected:
                raise SystemExit(
                    f"verdict mismatch under --drat on case {case}: Wassat={got}, CaDiCaL={expected}"
                )
            if expected == "SATISFIABLE":
                sat += 1
                if not satisfies(clauses, model(produced.stdout)):
                    raise SystemExit(f"invalid model under --drat on case {case}")
            else:
                unsat += 1
                checked = subprocess.run(
                    [WRAT, str(cnf), str(proof)], capture_output=True, text=True, timeout=TIMEOUT, check=False
                )
                if produced.returncode not in (0, 10, 20) or "s VERIFIED" not in checked.stdout:
                    raise SystemExit(
                        f"proof rejected on case {case}: {checked.stdout[-300:]} {checked.stderr[-300:]}"
                    )
                proofs += 1
    print(
        f"OK: {CASES} cases under the forced Kissat profile, {sat} SAT, {unsat} UNSAT, "
        f"{proofs} independently checked proofs"
    )


if __name__ == "__main__":
    main()
