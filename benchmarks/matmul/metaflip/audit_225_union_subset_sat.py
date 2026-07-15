#!/usr/bin/env python3
"""Independent structural and model audit for flipfleet_225_union_subset_sat.

This intentionally does not import the Tungsten implementation.  It rebuilds
all 400 rank-one columns, the matrix-multiplication target, the canonical Sinz
at-most-k counter, and (when present) the solver assignment from serialized
artifacts.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


def read_terms(path: Path) -> list[tuple[int, int, int]]:
    terms = []
    declared = None
    for raw in path.read_text().splitlines():
        if raw.startswith("# columns "):
            declared = int(raw.split()[-1])
        if not raw or raw.startswith("#"):
            continue
        index, u, v, w = map(int, raw.split())
        assert index == len(terms), (index, len(terms))
        assert 0 < u < 16 and 0 < v < 1024 and 0 < w < 1024
        terms.append((u, v, w))
    assert declared == len(terms)
    assert len(set(terms)) == len(terms)
    return terms


def column(term: tuple[int, int, int]) -> int:
    u, v, w = term
    result = 0
    for a in range(4):
        if (u >> a) & 1:
            for b in range(10):
                if (v >> b) & 1:
                    for c in range(10):
                        if (w >> c) & 1:
                            result ^= 1 << ((a * 10 + b) * 10 + c)
    return result


def target() -> int:
    result = 0
    for i in range(2):
        for j in range(2):
            a = i * 2 + j
            for k in range(5):
                b = j * 5 + k
                c = i * 5 + k
                result ^= 1 << ((a * 10 + b) * 10 + c)
    return result


def gf2_rank(columns: list[int]) -> int:
    pivots: dict[int, int] = {}
    for value in columns:
        while value:
            bit = (value & -value).bit_length() - 1
            if bit not in pivots:
                pivots[bit] = value
                break
            value ^= pivots[bit]
    return len(pivots)


def parse_xnf(path: Path):
    lines = path.read_text().splitlines()
    magic, kind, variables, clauses = lines[0].split()
    assert (magic, kind) == ("p", "cnf")
    body = lines[1:]
    assert len(body) == int(clauses)
    return int(variables), body


def expected_xors(columns: list[int]) -> list[str]:
    wanted = target()
    rows = []
    for cell in range(400):
        literals = [i + 1 for i, value in enumerate(columns) if (value >> cell) & 1]
        if not literals:
            assert not ((wanted >> cell) & 1), f"uncovered target cell {cell}"
            continue
        if not ((wanted >> cell) & 1):
            literals[0] = -literals[0]
        rows.append("x" + " ".join(map(str, literals)) + " 0")
    return rows


def seq_var(n: int, k: int, i: int, j: int) -> int:
    return n + (i - 1) * k + j


def expected_counter(n: int, k: int) -> list[str]:
    rows = []
    for i in range(1, n):
        rows.append(f"{-i} {seq_var(n, k, i, 1)} 0")
    for i in range(2, n):
        rows.append(f"{-seq_var(n, k, i - 1, 1)} {seq_var(n, k, i, 1)} 0")
        for j in range(2, k + 1):
            rows.append(
                f"{-i} {-seq_var(n, k, i - 1, j - 1)} "
                f"{seq_var(n, k, i, j)} 0"
            )
            rows.append(f"{-seq_var(n, k, i - 1, j)} {seq_var(n, k, i, j)} 0")
    for i in range(2, n + 1):
        rows.append(f"{-i} {-seq_var(n, k, i - 1, k)} 0")
    return rows


def read_model(path: Path) -> tuple[str, dict[int, bool] | None]:
    text = path.read_text()
    status_lines = {line.strip() for line in text.splitlines() if line.startswith("s ")}
    if "s UNSATISFIABLE" in status_lines:
        return "unsat-reported", None
    if "s SATISFIABLE" not in status_lines:
        return "indeterminate", None
    assignment = {}
    for line in text.splitlines():
        if not line.startswith("v "):
            continue
        for literal in map(int, line.split()[1:]):
            if not literal:
                continue
            variable = abs(literal)
            value = literal > 0
            assert variable not in assignment or assignment[variable] == value
            assignment[variable] = value
    return "sat", assignment


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("terms", type=Path)
    parser.add_argument("xnf", type=Path)
    parser.add_argument("--limit", type=int, required=True)
    parser.add_argument("--sha256")
    parser.add_argument("--rank", type=int)
    parser.add_argument("--model", type=Path)
    args = parser.parse_args()

    raw = args.terms.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if args.sha256:
        assert digest == args.sha256, (digest, args.sha256)
    terms = read_terms(args.terms)
    columns = [column(term) for term in terms]
    rank = gf2_rank(columns)
    if args.rank is not None:
        assert rank == args.rank, (rank, args.rank)

    variables, body = parse_xnf(args.xnf)
    xors = expected_xors(columns)
    counter = expected_counter(len(terms), args.limit)
    assert body == xors + counter
    assert variables == len(terms) + (len(terms) - 1) * args.limit

    model_status = "not-checked"
    selected = None
    if args.model:
        model_status, assignment = read_model(args.model)
        if model_status == "sat":
            assert assignment is not None
            assert all(variable in assignment for variable in range(1, variables + 1))
            chosen = [i for i in range(len(terms)) if assignment[i + 1]]
            assert len(chosen) <= args.limit
            reconstruction = 0
            for index in chosen:
                reconstruction ^= columns[index]
            assert reconstruction == target()
            selected = len(chosen)
            model_status = "sat-exact"

    print(
        "FF225_UNION_AUDIT_OK"
        f" terms={len(terms)} rank={rank} nullity={len(terms)-rank}"
        f" sha256={digest} xors={len(xors)} counter={len(counter)}"
        f" variables={variables} limit={args.limit}"
        f" model={model_status} selected={selected}"
    )


if __name__ == "__main__":
    main()
