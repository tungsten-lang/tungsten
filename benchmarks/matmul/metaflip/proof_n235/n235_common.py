#!/usr/bin/env python3
"""Independent finite geometry for the GF(2) ``<2,3,5>`` proof.

This module imports no code from Wang's searcher or verifier.  It parses only
the text certificate and independently expands its constrained-subspace
orbits under ``GL(2,2) x GL(3,2)``.  For compatibility with the older n324
geometry notation, certificate vectors are transposed from row-major 2x3 to
row-major 3x2 coordinates before expansion.
"""

from __future__ import annotations

import ast
import itertools
import re
from collections import Counter
from pathlib import Path


PROBLEM_NAME = "matrix_q02_n235"
EXPECTED_DIMS = (6, 15, 10)
EXPECTED_ORBITS_BY_DIM = {6: 1, 5: 2, 4: 7, 3: 11, 2: 7, 1: 2, 0: 1}


def rank_rows(rows: tuple[int, ...] | list[int], width: int = 6) -> int:
    xs = list(rows)
    rank = 0
    for bit in range(width - 1, -1, -1):
        pivot = next(
            (i for i in range(rank, len(xs)) if (xs[i] >> bit) & 1), None
        )
        if pivot is None:
            continue
        xs[rank], xs[pivot] = xs[pivot], xs[rank]
        for i in range(len(xs)):
            if i != rank and ((xs[i] >> bit) & 1):
                xs[i] ^= xs[rank]
        rank += 1
    return rank


def rref(rows: tuple[int, ...] | list[int], width: int = 6) -> tuple[int, ...]:
    xs = [value for value in rows if value]
    pivot_row = 0
    for bit in range(width - 1, -1, -1):
        pivot = next(
            (i for i in range(pivot_row, len(xs)) if (xs[i] >> bit) & 1),
            None,
        )
        if pivot is None:
            continue
        xs[pivot_row], xs[pivot] = xs[pivot], xs[pivot_row]
        for i in range(len(xs)):
            if i != pivot_row and ((xs[i] >> bit) & 1):
                xs[i] ^= xs[pivot_row]
        pivot_row += 1
    return tuple(sorted(value for value in xs if value))


def gl_rows(n: int) -> list[tuple[int, ...]]:
    return [
        rows
        for rows in itertools.product(range(1 << n), repeat=n)
        if rank_rows(list(rows), n) == n
    ]


def row_times(vector: int, packed: int, n: int) -> int:
    mask = (1 << n) - 1
    result = 0
    for i in range(n):
        if (vector >> i) & 1:
            result ^= (packed >> (n * i)) & mask
    return result


def apply_32(matrix: int, left: int, right: int) -> int:
    """Apply ``A -> left*A*right`` to a packed row-major 3x2 matrix."""
    rows = [(matrix >> (2 * i)) & 3 for i in range(3)]
    left_rows = []
    for i in range(3):
        selector = (left >> (3 * i)) & 7
        value = 0
        for k in range(3):
            if (selector >> k) & 1:
                value ^= rows[k]
        left_rows.append(value)
    return sum(
        row_times(left_rows[i], right, 2) << (2 * i) for i in range(3)
    )


def group_permutations() -> list[tuple[int, ...]]:
    lefts = [
        sum(row << (3 * i) for i, row in enumerate(rows))
        for rows in gl_rows(3)
    ]
    rights = [
        sum(row << (2 * i) for i, row in enumerate(rows))
        for rows in gl_rows(2)
    ]
    permutations = [
        tuple(apply_32(value, left, right) for value in range(64))
        for left in lefts
        for right in rights
    ]
    assert len(permutations) == 1008
    assert len(set(permutations)) == 1008
    assert all(sorted(permutation) == list(range(64)) for permutation in permutations)
    return permutations


def transpose_23_to_32(matrix: int) -> int:
    """Transpose a packed row-major 2x3 matrix into 3x2 coordinates."""
    result = 0
    for row in range(2):
        for column in range(3):
            if (matrix >> (3 * row + column)) & 1:
                result |= 1 << (2 * column + row)
    return result


def _top_level_blocks(text: str) -> list[str]:
    blocks: list[str] = []
    active: list[str] | None = None
    for line in text.splitlines():
        if line == "constrained_tensors {":
            assert active is None
            active = [line]
        elif active is not None:
            active.append(line)
            if line == "}":
                blocks.append("\n".join(active))
                active = None
    assert active is None
    return blocks


def parse_certificate(path: Path) -> list[tuple[tuple[int, ...], int]]:
    text = path.read_text()
    assert re.search(rf'(?m)^problem_name: "{PROBLEM_NAME}"$', text)
    assert re.search(r"(?m)^characteristic: 2$", text)
    assert re.search(r"(?m)^extension_degree: 1$", text)
    dims = tuple(
        int(re.search(rf"(?m)^{field}: (\d+)$", text).group(1))
        for field in ("na", "nb", "nc")
    )
    assert dims == EXPECTED_DIMS

    blocks = _top_level_blocks(text)
    assert len(blocks) == sum(EXPECTED_ORBITS_BY_DIM.values())
    parsed: list[tuple[tuple[int, ...], int]] = []
    indices: list[int] = []
    dimensions: list[int] = []
    for position, block in enumerate(blocks):
        index_match = re.search(r"(?m)^  index: (\d+)$", block)
        if position == 0 and index_match is None:
            indices.append(0)
        else:
            assert index_match is not None
            indices.append(int(index_match.group(1)))
        constraint_match = re.search(
            r'(?m)^  constraints: ("(?:[^"\\]|\\.)*")$', block
        )
        raw = (
            b""
            if constraint_match is None
            else ast.literal_eval("b" + constraint_match.group(1))
        )
        dimensions.append(len(raw))
        bound_match = re.search(r"(?m)^  rank_lower_bound: (\d+)$", block)
        assert bound_match is not None
        representative = rref(tuple(transpose_23_to_32(value) for value in raw))
        parsed.append((representative, int(bound_match.group(1))))
    assert indices == list(range(len(blocks)))
    assert dict(Counter(dimensions)) == EXPECTED_ORBITS_BY_DIM
    return parsed


def expand_certificate(path: Path) -> tuple[
    list[tuple[tuple[int, ...], int]],
    dict[tuple[int, ...], int],
    dict[tuple[int, ...], int],
]:
    parsed = parse_certificate(path)
    permutations = group_permutations()
    lower_bound_by_subspace: dict[tuple[int, ...], int] = {}
    orbit_by_subspace: dict[tuple[int, ...], int] = {}
    for orbit, (representative, bound) in enumerate(parsed):
        images = sorted(
            {
                rref(tuple(permutation[value] for value in representative))
                for permutation in permutations
            }
        )
        assert representative in images
        for image in images:
            old_bound = lower_bound_by_subspace.setdefault(image, bound)
            old_orbit = orbit_by_subspace.setdefault(image, orbit)
            assert old_bound == bound
            assert old_orbit == orbit
    # Gaussian-binomial count for all subspaces of F_2^6.
    assert len(lower_bound_by_subspace) == 2825
    return parsed, lower_bound_by_subspace, orbit_by_subspace


def span_elements(rows: tuple[int, ...]) -> list[int]:
    values = []
    for mask in range(1 << len(rows)):
        value = 0
        for i, row in enumerate(rows):
            if (mask >> i) & 1:
                value ^= row
        values.append(value)
    return values


def rank_32(matrix: int) -> int:
    return rank_rows([(matrix >> (2 * i)) & 3 for i in range(3)], 2)


RANK_ONE_A = tuple(value for value in range(1, 64) if rank_32(value) == 1)
RANK_TWO_A = tuple(value for value in range(1, 64) if rank_32(value) == 2)
assert len(RANK_ONE_A) == 21
assert len(RANK_TWO_A) == 42
