#!/usr/bin/env python3
"""Deterministic randomized differential and certificate test for Wassat."""

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
CASES = int(os.environ.get("CASES", "200"))
SEED = int(os.environ.get("SEED", "20260721"))
TIMEOUT = float(os.environ.get("TIMEOUT", "20"))


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


if not Path(WASSAT).is_file():
    raise SystemExit(f"Wassat binary not found: {WASSAT}")
if not Path(WRAT).is_file():
    raise SystemExit(
        f"tungsten-wrat binary not found: {WRAT}; certificate checking is mandatory"
    )
if not CADICAL:
    raise SystemExit("CaDiCaL not found; set CADICAL to run the differential test")

rng = random.Random(SEED)
sat_count = 0
unsat_count = 0
proof_count = 0

with tempfile.TemporaryDirectory(prefix="wassat-differential-") as directory:
    root = Path(directory)
    for case in range(CASES):
        clauses: list[list[int]] = []
        if case % 3 == 0:
            # Planted SAT, so model validation gets substantial coverage.
            nvars = rng.randint(5, 40)
            planted = {v: bool(rng.getrandbits(1)) for v in range(1, nvars + 1)}
            for _ in range(rng.randint(3 * nvars, 6 * nvars)):
                clause = []
                for _ in range(rng.randint(2, min(5, nvars))):
                    variable = rng.randint(1, nvars)
                    clause.append(variable if rng.getrandbits(1) else -variable)
                if not any((literal > 0) == planted[abs(literal)] for literal in clause):
                    clause[0] = 0 - clause[0]
                clauses.append(clause)
        elif case % 3 == 1:
            # Random 3-SAT straddling the phase transition.
            nvars = rng.randint(8, 40)
            for _ in range(rng.randint(3 * nvars, 6 * nvars)):
                variables = rng.sample(range(1, nvars + 1), 3)
                clauses.append([v if rng.getrandbits(1) else -v for v in variables])
        else:
            # A nontrivial guaranteed-UNSAT pigeonhole core, with its
            # variables randomly permuted to avoid one lucky fixed ordering.
            holes = rng.randint(2, 6)
            pigeons = holes + 1
            nvars = pigeons * holes
            permutation = list(range(1, nvars + 1))
            rng.shuffle(permutation)

            def variable(pigeon: int, hole: int) -> int:
                return permutation[pigeon * holes + hole]

            for pigeon in range(pigeons):
                clauses.append([variable(pigeon, hole) for hole in range(holes)])
            for hole in range(holes):
                for left in range(pigeons):
                    for right in range(left + 1, pigeons):
                        clauses.append([-variable(left, hole), -variable(right, hole)])

        # Exercise legal but awkward clause bodies without deciding the case:
        # duplicates and tautologies must not perturb the verdict.
        if clauses:
            source = rng.choice(clauses)
            clauses.append(source + [source[0]])
            tautology = rng.randint(1, nvars)
            clauses.append([tautology, -tautology])

        cnf = root / f"case-{case:04d}.cnf"
        cnf.write_text(
            f"p cnf {nvars} {len(clauses)}\n"
            + "".join(" ".join(map(str, clause)) + " 0\n" for clause in clauses)
        )
        ours = subprocess.run(
            [WASSAT, str(cnf), "--fast"], capture_output=True, text=True, timeout=TIMEOUT, check=False
        )
        reference = subprocess.run(
            [CADICAL, str(cnf)], capture_output=True, text=True, timeout=TIMEOUT, check=False
        )
        ours_verdict = verdict(ours.stdout)
        reference_verdict = verdict(reference.stdout)
        if ours_verdict != reference_verdict:
            raise SystemExit(
                f"verdict mismatch on {cnf}: Wassat={ours_verdict}, CaDiCaL={reference_verdict}"
            )
        if ours_verdict == "SATISFIABLE":
            sat_count += 1
            if not satisfies(clauses, model(ours.stdout)):
                raise SystemExit(f"invalid Wassat model on {cnf}")
        elif ours_verdict == "UNSATISFIABLE":
            unsat_count += 1
            proof = root / f"case-{case:04d}.drat"
            produced = subprocess.run(
                [WASSAT, str(cnf), "--drat", str(proof)],
                capture_output=True,
                text=True,
                timeout=TIMEOUT,
                check=False,
            )
            checked = subprocess.run(
                [WRAT, str(cnf), str(proof)],
                capture_output=True,
                text=True,
                timeout=TIMEOUT,
                check=False,
            )
            if produced.returncode != 0 or "s VERIFIED" not in checked.stdout:
                raise SystemExit(f"raw proof failed independent checking on {cnf}")
            proof_count += 1
        else:
            raise SystemExit(f"missing Wassat verdict on {cnf}: {ours.stdout}{ours.stderr}")

print(
    f"OK: {CASES} deterministic cases, {sat_count} SAT models, "
    f"{unsat_count} UNSAT verdicts, {proof_count} independently checked raw proofs"
)
