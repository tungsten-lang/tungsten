#!/usr/bin/env python3
"""Independently decode and check a necessary-B PB model, then solve for C."""

from __future__ import annotations

import argparse
from pathlib import Path

from n324_common import RANK_ONE_A, rank32, rank_rows


def parse_model(path: Path) -> set[int]:
    positive = set()
    saw_sat = False
    for line in path.read_text().splitlines():
        if line == "s SATISFIABLE":
            saw_sat = True
        if not line.startswith("v "):
            continue
        for token in line.split()[1:]:
            if token.startswith("x"):
                positive.add(int(token[1:]))
            elif token.startswith("-x"):
                continue
            else:
                raise AssertionError(token)
    assert saw_sat and positive
    return positive


def linear_c_rank(a: tuple[int, ...], b: list[int]) -> tuple[bool, int]:
    variables = 19 * 12
    basis: dict[int, int] = {}
    for ai in range(6):
        i, j = divmod(ai, 2)
        for bj in range(8):
            jb, k = divmod(bj, 4)
            for ck in range(12):
                kc, ic = divmod(ck, 3)
                rhs = int(j == jb and k == kc and i == ic)
                row = rhs << variables
                for term in range(19):
                    if ((a[term] >> ai) & 1) and ((b[term] >> bj) & 1):
                        row ^= 1 << (term * 12 + ck)
                while row & ((1 << variables) - 1):
                    pivot = (row & ((1 << variables) - 1)).bit_length() - 1
                    if pivot not in basis:
                        basis[pivot] = row
                        break
                    row ^= basis[pivot]
                else:
                    if (row >> variables) & 1:
                        return False, len(basis)
    return True, len(basis)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("occurrence_table", type=Path)
    parser.add_argument("model", type=Path)
    parser.add_argument("--missing", nargs=2, type=int, required=True)
    parser.add_argument("--fixed-b", type=int)
    args = parser.parse_args()

    missing = tuple(args.missing)
    assert missing in ((1, 2), (1, 4), (1, 8))
    a = tuple(value for value in RANK_ONE_A if value not in missing)
    assert len(a) == len(set(a)) == 19
    canonical_a = {(1, 2): 3, (1, 4): 5, (1, 8): 15}[missing]
    canonical_term = a.index(canonical_a)
    rank_one_b = tuple(
        value
        for value in range(1, 256)
        if rank_rows([value & 15, value >> 4], 4) == 1
    )
    assert len(rank_one_b) == 45
    positive = parse_model(args.model)

    b = []
    for term in range(19):
        selected = [
            value
            for offset, value in enumerate(rank_one_b)
            if term * 45 + offset + 1 in positive
        ]
        assert len(selected) == 1, (term, selected)
        b.append(selected[0])
    if args.fixed_b is not None:
        assert b[canonical_term] == args.fixed_b

    rows = []
    for line in args.occurrence_table.read_text().splitlines():
        values = tuple(map(int, line.split()))
        rows.append((values[0], set(values[1:])))
    assert len(rows) == 56724
    for capacity, points in rows:
        assert sum(value in points for value in b) <= capacity

    rank_two_a = [value for value in range(1, 64) if rank32(value) == 2]
    assert len(rank_two_a) == 42
    for functional_a in rank_two_a:
        active = [
            b[term]
            for term, avalue in enumerate(a)
            if (functional_a & avalue).bit_count() & 1
        ]
        assert rank_rows(active, 8) == 8

    consistent, rank = linear_c_rank(a, b)
    print(
        f"missing={missing} B_assignment={' '.join(map(str, b))} "
        f"occurrence_rows=56724 B_span_checks=42 PASS"
    )
    print(
        f"linear_C_consistent={int(consistent)} rank={rank} "
        f"variables=228 nullity={228-rank if consistent else 'n/a'}"
    )


if __name__ == "__main__":
    main()
