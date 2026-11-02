#!/usr/bin/env python3
"""Satisfiable adversarial inputs must never pass a structural UNSAT shortcut.

Run with a solver command, for example:
  python3 structural_unsat_test.py /path/to/wassat
The remaining arguments form the command, allowing an interpreted entry point
to exercise the same CLI contract.
"""

from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys
import tempfile

from sc2026 import competition_output, lane_of, model_satisfies


def fingerprint_collision() -> list[list[int]]:
    """Match the removed AProVE fingerprint with an explicit satisfying model.

    Only variables 8500, 11293, and 21732 are true. The rest of the clauses
    contain only negative literals on other variables. Duplicate literals are
    legal DIMACS and count toward the fingerprint just as original literals do.
    """
    clauses = [[21732]]
    clauses.extend([[-21732, 8500] for _ in range(223)])
    clauses.append([-21732, 11293])
    clauses.append([-17200] * 114 + [-18016])
    remaining_413 = 111194
    for index in range(79540):
        size = 3 if index < 51632 else 2
        take = min(size, remaining_413)
        clauses.append([-413] * take + [-412] * (size - take))
        remaining_413 -= take
    assert remaining_413 == 0

    # Pin every condition of the old recognizer. A fixture that stops matching
    # the old fingerprint would silently stop guarding this wrong-UNSAT path.
    heads = [c[1] if c[0] == -21732 else c[0]
             for c in clauses if len(c) == 2 and -21732 in c]
    wide = [c for c in clauses if len(c) == 115]
    assert len(clauses) == 79766
    assert [21732] in clauses
    assert len(heads) == 224 and sum(heads) == 1906793
    assert len(wide) == 1 and sum(wide[0]) == -1978816
    assert sum(map(len, clauses)) == 211276
    assert sum(map(sum, clauses)) == -91842797
    planted = {8500, 11293, 21732}
    assert all(any((abs(lit) in planted) == (lit > 0) for lit in c)
               for c in clauses)
    return clauses


def sgi_fixture(binary: bool, unsat: bool = False) -> tuple[int, list[list[int]], dict[int, bool]]:
    """Two pattern edges allow disjoint host edges, but the CNF is SAT.

    Intersecting those different host graphs invents an empty host graph and
    falsely refutes the input. Each pair's projected restrictions must instead
    be justified by that pair's original clauses.
    """
    count = 21 if binary else 22
    width = 5 if binary else 30
    nvars = count * width

    def variable(p: int, bit: int) -> int:
        return p * width + bit + 1

    def forbid_value(p: int, value: int) -> list[int]:
        if not binary:
            return [-variable(p, value)]
        return [-variable(p, bit) if value & (1 << bit) else variable(p, bit)
                for bit in range(5)]

    clauses = []
    for p in range(count):
        if binary:
            clauses.extend([forbid_value(p, 30), forbid_value(p, 31)])
        else:
            clauses.append([variable(p, h) for h in range(30)])
    for p in range(count):
        for q in range(p + 1, count):
            for h in range(30):
                clauses.append(forbid_value(p, h) + forbid_value(q, h))
    edges = ((0, 1),) if unsat else ((0, 1), (2, 3))
    for p, q in edges:
        for h in range(30):
            for k in range(30):
                # The positive UNSAT control forbids every value pair on
                # edge 0-1. Those original clauses justify an empty host graph.
                if h != k and (unsat or {h, k} != {p, q}):
                    clauses.append(forbid_value(p, h) + forbid_value(q, k))
    padding = forbid_value(0, 0) + forbid_value(1, 0)
    minimum_clauses = 40000 if binary else 50000
    clauses.extend([padding.copy() for _ in range(minimum_clauses - len(clauses))])
    # Pattern vertex p maps to host vertex p in both representations.
    planted = {variable(p, bit): bool(p & (1 << bit)) if binary else bit == p
               for p in range(count) for bit in range(width)}
    if not unsat:
        assert all(any(planted[abs(lit)] == (lit > 0) for lit in clause)
                   for clause in clauses)
    return nvars, clauses, planted


def circuit_relation_collision(ascon: bool) -> tuple[int, list[list[int]], dict[int, bool]]:
    """Both output polarities can occur without defining an output function.

    The sinks are forced true, but their other clauses are already satisfied
    by a fixed true input. Evaluating positive-output clauses as an equality
    incorrectly assigns those sinks false. The all-true model satisfies every
    original clause in both fixtures.
    """
    if ascon:
        nvars, target = 100000, 200000
        clauses = [[32]]
        for value in range(66, 72):
            gate = value + 24
            clauses.extend([[gate, -value], [-gate, value]])
        for gate in range(100, 164):
            clauses.extend([[gate], [gate, 32], [-gate, 32]])
        clauses.extend([[32] for _ in range(target - len(clauses) - 1)])
        clauses.append([32, -nvars])
    else:
        nvars, target = 120100, 360300
        clauses = [[1], [2], [3], [4]] + [[v] for v in range(47, 73)]
        for gate in range(73, 120000):
            clauses.extend([[gate, -41], [-gate, 41]])
        for gate in range(120000, 120016):
            clauses.extend([[gate], [gate, 1], [-gate, 1]])
        clauses.extend([[nvars, 1] for _ in range(target - len(clauses))])
    assert len(clauses) == target
    assert all(any(lit > 0 for lit in clause) for clause in clauses)
    return nvars, clauses, {v: True for v in range(1, nvars + 1)}


def gray_miter_collision(kind: int) -> tuple[int, list[list[int]], dict[int, bool]]:
    """A miter output may be allowed without being forced by its clauses."""
    assert kind in (0, 1, 2)
    if kind == 2:
        # Both clauses on gate 29 are tautologies. Treating the last output
        # occurrence as its polarity invents a function for this free gate.
        clauses = [[29, -29, 1], [29, -29, -1]]
        for gate in range(30, 501):
            clauses.extend([[gate, -29], [-gate, 29]])
        clauses.append([-500])
        padding = [30, -29]
        planted = {v: v < 29 for v in range(1, 501)}
    else:
        clauses = []
        for gate in range(29, 500):
            clauses.extend([[gate, -1], [-gate, 1]])
        # Each output clause is satisfied by its inputs for every row.
        # Either output is therefore allowed, including the forced unit.
        clauses.extend([[500, 1, -1], [-500, 1, -1], [500 if kind == 0 else -500]])
        padding = [29, -1]
        planted = {v: v != 500 or kind == 0 for v in range(1, 501)}
    clauses.extend([padding.copy() for _ in range(1500 - len(clauses))])
    assert all(any(planted[abs(lit)] == (lit > 0) for lit in clause)
               for clause in clauses)
    return 500, clauses, planted


def covering_collision() -> tuple[int, list[list[int]], dict[int, bool]]:
    """Positive-row incidence does not imply a negative binary conflict.

    Variables 1 and 2 cover every row together. Adding conflicts between each
    row's first variable and its tail invents a complete conflict graph, in
    which no singleton can cover the first four rows.
    """
    nvars = 350
    clauses = [[1, 2, 3], [2, 3, 4], [3, 4, 1], [4, 1, 2]]
    clauses.extend([[v, 1, 2] for v in range(5, nvars + 1)])
    clauses.extend([[-u, -v] for u in range(2, nvars + 1)
                    for v in range(u + 1, nvars + 1)])
    planted = {v: v <= 2 for v in range(1, nvars + 1)}
    assert all(any(planted[abs(lit)] == (lit > 0) for lit in c) for c in clauses)
    return nvars, clauses, planted


def main() -> None:
    command = sys.argv[1:]
    if not command:
        raise SystemExit("usage: structural_unsat_test.py <solver command...>")
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("WASSAT_", "TUNGSTEN_"))}
    repo = Path(__file__).resolve().parents[3]
    wrat = Path(os.environ.get("WRAT", repo / "bits/tungsten-wrat/bin/wrat"))
    if not wrat.is_file():
        raise SystemExit("WRAT proof checker not found; set WRAT")
    fixtures = [("fingerprint-collision", 21734, fingerprint_collision(),
                 {v: v in (8500, 11293, 21732) for v in range(1, 21735)})]
    for binary in (False, True):
        fixtures.append(("sgi-log" if binary else "sgi-onehot", *sgi_fixture(binary)))
    for ascon in (False, True):
        fixtures.append(("ascon-relation" if ascon else "satcoin-relation",
                         *circuit_relation_collision(ascon)))
    for kind, name in enumerate(("gray-output-positive", "gray-output-negative", "gray-repeated-output")):
        fixtures.append((name, *gray_miter_collision(kind)))
    fixtures.append(("covering-invented-conflicts", *covering_collision()))
    with tempfile.TemporaryDirectory(prefix="wassat-unsat-soundness-") as tmp:
        root = Path(tmp)
        for name, nvars, clauses, planted in fixtures:
            source = root / (name + ".cnf")
            source.write_text(f"p cnf {nvars} {len(clauses)}\n" + "".join(
                " ".join(map(str, clause)) + " 0\n" for clause in clauses))
            assert model_satisfies(source, planted), "fixture model failed original CNF replay"

            for tables, mode in (("0", "fast"), ("1", "fast"), ("0", "drat")):
                env["WASSAT_BACKDOOR_TABLES"] = tables
                proof = root / "out.drat"
                args = ["--fast"] if mode == "fast" else ["--drat", str(proof)]
                result = subprocess.run([*command, str(source), *args], env=env,
                                        capture_output=True, text=True, timeout=60)
                assert result.returncode == 10, (
                    name, tables, mode, result.returncode, result.stdout, result.stderr)
                verdict, model, error = competition_output(result.stdout)
                assert error is None and verdict == "sat", (error, result.stdout)
                assert model_satisfies(source, model), "solver model failed original CNF replay"
                assert not proof.exists(), "SAT left an UNSAT certificate"
                print(f"{name}: tables={tables} mode={mode} SAT/model checked")

        for binary in (False, True):
            name = "sgi-log-unsat" if binary else "sgi-onehot-unsat"
            nvars, clauses, _ = sgi_fixture(binary, unsat=True)
            source = root / (name + ".cnf")
            source.write_text(f"p cnf {nvars} {len(clauses)}\n" + "".join(
                " ".join(map(str, clause)) + " 0\n" for clause in clauses))
            env["WASSAT_BACKDOOR_TABLES"] = "0"
            proof = root / (name + ".drat")
            for args in (["--fast"], ["--drat", str(proof)]):
                result = subprocess.run([*command, str(source), *args], env=env,
                                        capture_output=True, text=True, timeout=60)
                assert result.returncode == 20, (
                    name, args, result.returncode, result.stdout, result.stderr)
                verdict, _, error = competition_output(result.stdout)
                assert error is None and verdict == "unsat", (error, result.stdout)
                if args[0] == "--fast":
                    assert lane_of(result.stdout) == "sgi_mcsplit", result.stdout
            assert proof.is_file(), "proof mode did not produce a certificate"
            checked = subprocess.run([str(wrat), str(source), str(proof)], env=env,
                                     capture_output=True, text=True, timeout=60)
            assert checked.returncode == 0, (checked.stdout, checked.stderr)
            assert "s VERIFIED" in checked.stdout.splitlines(), (checked.stdout, checked.stderr)
            print(f"{name}: structural refutation and original-CNF DRAT replay checked")


if __name__ == "__main__":
    main()
