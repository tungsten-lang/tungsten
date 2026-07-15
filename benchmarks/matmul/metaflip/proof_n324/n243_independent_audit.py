#!/usr/bin/env python3
"""Independent finite-geometry/table audit for the n243 rank-two lemma."""

from __future__ import annotations

import ast
import argparse
import itertools
import re
import sys
from collections import Counter
from pathlib import Path


WIDTH = 8
BASE = 18
Q_BITS = (0, 1, 2, 3, 5, 6, 7)


def rank_rows(rows: tuple[int, ...] | list[int], width: int = WIDTH) -> int:
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


def rref(rows: tuple[int, ...] | list[int], width: int = WIDTH) -> tuple[int, ...]:
    xs = [x for x in rows if x]
    pivot_row = 0
    for bit in range(width - 1, -1, -1):
        pivot = next(
            (i for i in range(pivot_row, len(xs)) if (xs[i] >> bit) & 1), None
        )
        if pivot is None:
            continue
        xs[pivot_row], xs[pivot] = xs[pivot], xs[pivot_row]
        for i in range(len(xs)):
            if i != pivot_row and ((xs[i] >> bit) & 1):
                xs[i] ^= xs[pivot_row]
        pivot_row += 1
    return tuple(sorted(xs))


def gl_rows(n: int) -> list[tuple[int, ...]]:
    return [
        rows
        for rows in itertools.product(range(1 << n), repeat=n)
        if rank_rows(list(rows), n) == n
    ]


def row_times(v: int, rows: tuple[int, ...]) -> int:
    out = 0
    for i, row in enumerate(rows):
        if (v >> i) & 1:
            out ^= row
    return out


def apply_matrix(value: int, left: tuple[int, int], right: tuple[int, ...]) -> int:
    rows = (row_times(value & 15, right), row_times(value >> 4, right))
    return row_times(left[0], rows) | (row_times(left[1], rows) << 4)


def parse_certificate(path: Path) -> list[tuple[tuple[int, ...], int]]:
    blocks = path.read_text().split("constrained_tensors {")[1:]
    result = []
    for block in blocks:
        block = block.split("\n}", 1)[0]
        constraints = re.search(
            r'^\s*constraints: ("(?:[^"\\]|\\.)*")', block, re.M
        )
        bound = re.search(r"^\s*rank_lower_bound: (\d+)", block, re.M)
        assert bound is not None
        raw = b"" if constraints is None else ast.literal_eval("b" + constraints.group(1))
        result.append((rref(tuple(raw)), int(bound.group(1))))
    return result


def expand_certificate(
    path: Path,
) -> tuple[list[tuple[tuple[int, ...], int]], dict[tuple[int, ...], int]]:
    parsed = parse_certificate(path)
    assert len(parsed) == 86
    assert parsed[84] == ((BASE,), 18)
    lefts, rights = gl_rows(2), gl_rows(4)
    assert len(lefts) == 6 and len(rights) == 20160
    bounds: dict[tuple[int, ...], int] = {}
    for orbit, (representative, bound) in enumerate(parsed):
        minimum = None
        images = set()
        for right in rights:
            right_images = tuple(
                apply_matrix(x, (1, 2), right) for x in representative
            )
            for left in lefts:
                # right_images already includes the 4x4 action; apply only the
                # 2x2 action here rather than repeating the row products.
                transformed = []
                for x in right_images:
                    rows = (x & 15, x >> 4)
                    transformed.append(
                        row_times(left[0], rows) | (row_times(left[1], rows) << 4)
                    )
                image = rref(transformed)
                images.add(image)
                minimum = image if minimum is None or image < minimum else minimum
        assert representative == minimum, (orbit, representative, minimum)
        for image in images:
            old = bounds.setdefault(image, bound)
            assert old == bound, (orbit, image, old, bound)
        print(
            f"orbit={orbit} dim={len(representative)} "
            f"images={len(images)} bound={bound}"
        )
    expected_by_dim = {
        0: 1,
        1: 255,
        2: 10795,
        3: 97155,
        4: 200787,
        5: 97155,
        6: 10795,
        7: 255,
        8: 1,
    }
    actual_by_dim = Counter(map(len, bounds))
    assert dict(sorted(actual_by_dim.items())) == expected_by_dim
    assert len(bounds) == 417199
    return parsed, bounds


def span_elements(rows: tuple[int, ...]) -> list[int]:
    values = [0]
    for row in rows:
        values += [x ^ row for x in values]
    return values


def quotient(value: int) -> int:
    if (value >> 4) & 1:
        value ^= BASE
    return sum(((value >> bit) & 1) << i for i, bit in enumerate(Q_BITS))


def audit_table(bounds: dict[tuple[int, ...], int], table_path: Path) -> None:
    expected = set()
    containing = 0
    for subspace, bound in bounds.items():
        if rank_rows(subspace + (BASE,)) != len(subspace):
            continue
        containing += 1
        points = tuple(sorted({quotient(x) for x in span_elements(subspace)} - {0}))
        capacity = 18 - bound
        assert capacity >= 0
        if capacity < len(points):
            expected.add((capacity, points))
    actual = set()
    lines = table_path.read_text().splitlines()
    for line in lines:
        values = tuple(map(int, line.split()))
        actual.add((values[0], values[1:]))
    assert len(actual) == len(lines)
    assert containing == 29212
    assert len(expected) == 28480
    assert actual == expected
    print(
        f"all_subspaces={len(bounds)} containing_base={containing} "
        f"table_rows={len(actual)}"
    )


def write_occurrence_table(
    bounds: dict[tuple[int, ...], int], output_path: Path
) -> None:
    """Write all strongest B-subspace occurrence bounds for rank 19.

    If U is a constrained B-subspace with certified lower bound L(U), a
    rank-19 decomposition has at most 19-L(U) terms whose B factor lies in U.
    Only the 45 nonzero rank-one B forms can occur in the residual.
    """
    rank_one_b = tuple(
        value
        for value in range(1, 256)
        if rank_rows([value & 15, value >> 4], 4) == 1
    )
    assert len(rank_one_b) == 45
    strongest: dict[tuple[int, ...], int] = {}
    for subspace, bound in bounds.items():
        elements = set(span_elements(subspace))
        points = tuple(value for value in rank_one_b if value in elements)
        if not points:
            continue
        capacity = 19 - bound
        assert capacity >= 0
        old = strongest.get(points)
        if old is None or capacity < old:
            strongest[points] = capacity

    rows = sorted((capacity, points) for points, capacity in strongest.items())
    output_path.write_text(
        "".join(
            f"{capacity} {' '.join(map(str, points))}\n"
            for capacity, points in rows
        )
    )
    singleton = {
        points[0]: capacity
        for capacity, points in rows
        if len(points) == 1
    }
    assert len(singleton) == 45 and set(singleton.values()) == {2}
    print(
        f"occurrence_rows={len(rows)} singleton_rows={len(singleton)} "
        "singleton_capacity=2"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("certificate", type=Path)
    parser.add_argument("capacity_table", type=Path)
    parser.add_argument("--occurrence-table", type=Path)
    args = parser.parse_args()
    parsed, bounds = expand_certificate(args.certificate)
    assert parsed[83] == ((1,), 17)
    audit_table(bounds, args.capacity_table)
    if args.occurrence_table:
        write_occurrence_table(bounds, args.occurrence_table)


if __name__ == "__main__":
    main()
