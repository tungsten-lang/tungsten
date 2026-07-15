#!/usr/bin/env python3
"""Generate the exact capacity CNF proving n324 orbit 29 has rank >= 19.

The 31 primary variables are the nonzero points of F_2^6/<6>.  Every
subspace U containing the base S=<6> supplies the necessary-and-sufficient
open-state inequality

    |X intersect (U/S)| <= 18 - certified_lower_bound(U).

Duplicate occurrences already close by substitution, so X is a set.  The
final constraint |X| >= 18 asks for an open depth-18 state.  UNSAT proves that
the published orbit-29 lower bound 18 increments to 19.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

from n324_common import expand_certificate, rank_rows, span_elements


class Cnf:
    def __init__(self, initial_vars: int):
        self.nvars = initial_vars
        self.clauses: list[list[int]] = []

    def var(self) -> int:
        self.nvars += 1
        return self.nvars

    def add(self, *lits: int) -> None:
        self.clauses.append(list(lits))

    def at_most(self, lits: list[int], k: int) -> None:
        """Sinz sequential-counter encoding."""
        n = len(lits)
        if k < 0:
            self.add()
            return
        if k >= n:
            return
        if k == 0:
            for lit in lits:
                self.add(-lit)
            return
        s = [[self.var() for _ in range(k)] for _ in range(n - 1)]
        for i in range(n - 1):
            self.add(-lits[i], s[i][0])
        for i in range(1, n - 1):
            self.add(-s[i - 1][0], s[i][0])
            for j in range(1, k):
                self.add(-lits[i], -s[i - 1][j - 1], s[i][j])
                self.add(-s[i - 1][j], s[i][j])
        for i in range(1, n):
            self.add(-lits[i], -s[i - 1][k - 1])

    def dimacs(self, comments: list[str]) -> bytes:
        lines = [f"c {comment}" for comment in comments]
        lines.append(f"p cnf {self.nvars} {len(self.clauses)}")
        lines.extend(" ".join(map(str, clause)) +
                     (" " if clause else "") + "0"
                     for clause in self.clauses)
        return ("\n".join(lines) + "\n").encode()


def build(certificate: Path) -> tuple[bytes, dict[str, object]]:
    parsed, lb_by_subspace, orbit_by_subspace = expand_certificate(certificate)
    base = (6,)
    assert parsed[29] == (base, 18)
    points = sorted({min(x, x ^ 6) for x in range(1, 64)
                     if min(x, x ^ 6)})
    assert len(points) == 31
    point_var = {point: i + 1 for i, point in enumerate(points)}
    capacities = []
    for subspace, bound in lb_by_subspace.items():
        if rank_rows(subspace + base) != len(subspace):
            continue
        qpoints = sorted({min(x, x ^ 6) for x in span_elements(subspace)
                          if min(x, x ^ 6)})
        capacity = 18 - bound
        assert capacity >= 0
        capacities.append((subspace, orbit_by_subspace[subspace], bound,
                           capacity, qpoints))
    assert len(capacities) == 374

    cnf = Cnf(31)
    for _, _, _, capacity, qpoints in capacities:
        cnf.at_most([point_var[point] for point in qpoints], capacity)
    # At least 18 selected iff at most 13 of 31 point variables are false.
    cnf.at_most([-point_var[point] for point in points], 13)
    cert_hash = hashlib.sha256(certificate.read_bytes()).hexdigest()
    data = cnf.dimacs([
        "GF(2) <3,2,4> orbit-29 open-depth-18 capacity instance",
        f"certificate_sha256 {cert_hash}",
        "base_constraint 6 base_lb 18 target 19",
        f"points {' '.join(map(str, points))}",
        "374 subspaces containing base; each enforces count <= 18-certified_lb",
        "final sequential counter enforces selected count >= 18",
    ])
    return data, {
        "certificate_sha256": cert_hash,
        "cnf_sha256": hashlib.sha256(data).hexdigest(),
        "variables": cnf.nvars,
        "clauses": len(cnf.clauses),
        "capacity_constraints": len(capacities),
        "points": points,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("certificate", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    data, metadata = build(args.certificate)
    args.output.write_bytes(data)
    for key, value in metadata.items():
        print(f"{key}={value}")


if __name__ == "__main__":
    main()
