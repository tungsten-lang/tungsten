#!/usr/bin/env python3
"""Independent finite-geometry helpers for the GF(2) <3,2,4> proof.

This module intentionally imports no implementation code from Wang's prover.
It consumes only the published text-format certificate table.
"""

from __future__ import annotations

import ast
import itertools
import re
from pathlib import Path


def rank_rows(rows: tuple[int, ...] | list[int], width: int = 6) -> int:
    xs = list(rows)
    rank = 0
    for bit in range(width - 1, -1, -1):
        pivot = next((i for i in range(rank, len(xs))
                      if (xs[i] >> bit) & 1), None)
        if pivot is None:
            continue
        xs[rank], xs[pivot] = xs[pivot], xs[rank]
        for i in range(len(xs)):
            if i != rank and ((xs[i] >> bit) & 1):
                xs[i] ^= xs[rank]
        rank += 1
    return rank


def rref(rows: tuple[int, ...] | list[int], width: int = 6) -> tuple[int, ...]:
    xs = [x for x in rows if x]
    pivot_row = 0
    for bit in range(width - 1, -1, -1):
        pivot = next((i for i in range(pivot_row, len(xs))
                      if (xs[i] >> bit) & 1), None)
        if pivot is None:
            continue
        xs[pivot_row], xs[pivot] = xs[pivot], xs[pivot_row]
        for i in range(len(xs)):
            if i != pivot_row and ((xs[i] >> bit) & 1):
                xs[i] ^= xs[pivot_row]
        pivot_row += 1
    return tuple(sorted(x for x in xs if x))


def rank_square(packed: int, n: int) -> int:
    mask = (1 << n) - 1
    return rank_rows([(packed >> (n * i)) & mask for i in range(n)], n)


def inverse_square(packed: int, n: int) -> int:
    mask = (1 << n) - 1
    rows = [((packed >> (n * i)) & mask) | (1 << (n + i))
            for i in range(n)]
    for bit in range(n):
        pivot = next(i for i in range(bit, n) if (rows[i] >> bit) & 1)
        rows[bit], rows[pivot] = rows[pivot], rows[bit]
        for i in range(n):
            if i != bit and ((rows[i] >> bit) & 1):
                rows[i] ^= rows[bit]
    return sum(((rows[i] >> n) & mask) << (n * i) for i in range(n))


def gl_packed(n: int) -> list[int]:
    return [x for x in range(1 << (n * n)) if rank_square(x, n) == n]


def gl_rows(n: int) -> list[tuple[int, ...]]:
    return [rows for rows in itertools.product(range(1 << n), repeat=n)
            if rank_rows(list(rows), n) == n]


def row_times(v: int, packed: int, n: int) -> int:
    mask = (1 << n) - 1
    out = 0
    for i in range(n):
        if (v >> i) & 1:
            out ^= (packed >> (n * i)) & mask
    return out


def apply_a(a: int, left: int, right: int) -> int:
    """Apply A -> left*A*right to a row-major packed 3x2 matrix."""
    arows = [(a >> (2 * i)) & 3 for i in range(3)]
    left_rows = []
    for i in range(3):
        value = 0
        selector = (left >> (3 * i)) & 7
        for k in range(3):
            if (selector >> k) & 1:
                value ^= arows[k]
        left_rows.append(value)
    return sum(row_times(left_rows[i], right, 2) << (2 * i)
               for i in range(3))


def group_perms() -> list[tuple[int, ...]]:
    # Preserve the lexicographic row-tuple ordering used by the original
    # independent proof run so regenerated DIMACS files are byte-identical.
    lefts = [sum(row << (3 * i) for i, row in enumerate(rows))
             for rows in gl_rows(3)]
    rights = [sum(row << (2 * i) for i, row in enumerate(rows))
              for rows in gl_rows(2)]
    perms = [tuple(apply_a(x, left, right) for x in range(64))
             for left in lefts for right in rights]
    assert len(perms) == 1008 and len(set(perms)) == 1008
    assert all(sorted(p) == list(range(64)) for p in perms)
    return perms


def parse_certificate(path: Path) -> list[tuple[tuple[int, ...], int]]:
    text = path.read_text()
    blocks = text.split("constrained_tensors {")[1:]
    out = []
    for block in blocks:
        block = block.split("\n}", 1)[0]
        constraints = re.search(
            r'^\s*constraints: ("(?:[^"\\]|\\.)*")', block, re.M)
        bound = re.search(r'^\s*rank_lower_bound: (\d+)', block, re.M)
        assert bound is not None
        raw = b"" if constraints is None else ast.literal_eval(
            "b" + constraints.group(1))
        out.append((rref(tuple(raw)), int(bound.group(1))))
    return out


def expand_certificate(path: Path) -> tuple[
        list[tuple[tuple[int, ...], int]],
        dict[tuple[int, ...], int],
        dict[tuple[int, ...], int]]:
    """Return parsed orbits, subspace->LB, and subspace->orbit index."""
    perms = group_perms()
    parsed = parse_certificate(path)
    assert len(parsed) == 31
    lb_by_subspace: dict[tuple[int, ...], int] = {}
    orbit_by_subspace: dict[tuple[int, ...], int] = {}
    for orbit, (representative, bound) in enumerate(parsed):
        images = [rref(tuple(p[x] for x in representative)) for p in perms]
        assert representative == min(images)
        for image in images:
            old_bound = lb_by_subspace.setdefault(image, bound)
            old_orbit = orbit_by_subspace.setdefault(image, orbit)
            assert old_bound == bound and old_orbit == orbit
    # Gaussian-binomial total for all subspaces of F_2^6.
    assert len(lb_by_subspace) == 2825
    return parsed, lb_by_subspace, orbit_by_subspace


def span_elements(rows: tuple[int, ...]) -> list[int]:
    out = []
    for mask in range(1 << len(rows)):
        value = 0
        for i, row in enumerate(rows):
            if (mask >> i) & 1:
                value ^= row
        out.append(value)
    return out


def rank32(x: int) -> int:
    rows = [x & 3, (x >> 2) & 3, (x >> 4) & 3]
    return rank_rows(rows, 2)


RANK_ONE_A = tuple(x for x in range(1, 64) if rank32(x) == 1)
assert len(RANK_ONE_A) == 21
