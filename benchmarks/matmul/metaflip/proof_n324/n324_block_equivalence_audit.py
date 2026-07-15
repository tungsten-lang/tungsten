#!/usr/bin/env python3
"""Independent audit of the 12 identical 48x19 n324 C-system blocks."""

from __future__ import annotations

import argparse
import collections
import re
from pathlib import Path

from n324_common import RANK_ONE_A, rank_rows


def positive_model(path: Path) -> set[int]:
    text = path.read_text()
    assert re.search(r"^s SATISFIABLE$", text, re.M)
    result = set()
    for line in text.splitlines():
        if not line.startswith("v "):
            continue
        for token in line.split()[1:]:
            if token.startswith("x"):
                result.add(int(token[1:]))
            else:
                assert token.startswith("-x")
    return result


def dependencies(rows: list[tuple[int, int]]) -> tuple[int, list[tuple[int, int]]]:
    basis = {}
    result = []
    for index, (variables, rhs) in enumerate(rows):
        provenance = 1 << index
        while variables:
            pivot = variables.bit_length() - 1
            if pivot not in basis:
                basis[pivot] = variables, rhs, provenance
                break
            old_variables, old_rhs, old_provenance = basis[pivot]
            variables ^= old_variables
            rhs ^= old_rhs
            provenance ^= old_provenance
        else:
            result.append((provenance, rhs))
    return len(basis), result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive_dir", type=Path)
    parser.add_argument("--missing", nargs=2, type=int, required=True)
    args = parser.parse_args()
    missing = tuple(args.missing)
    a = tuple(value for value in RANK_ONE_A if value not in missing)
    bvalues = tuple(
        value
        for value in range(1, 256)
        if rank_rows([value & 15, value >> 4], 4) == 1
    )
    models = sorted(args.archive_dir.glob("iter[0-9][0-9][0-9].out"))
    # Ignore a final UNSAT/time-limit result if a future archive contains one.
    models = [path for path in models if re.search(r"^s SATISFIABLE$", path.read_text(), re.M)]
    assert models
    ranks = collections.Counter()
    contradiction_counts = []
    for path in models:
        positive = positive_model(path)
        b = []
        for term in range(19):
            selected = [
                value
                for offset, value in enumerate(bvalues)
                if term * 45 + offset + 1 in positive
            ]
            assert len(selected) == 1
            b.append(selected[0])

        block_rows = []
        for ai in range(6):
            for bj in range(8):
                block_rows.append(
                    sum(
                        1 << term
                        for term in range(19)
                        if ((a[term] >> ai) & 1) and ((b[term] >> bj) & 1)
                    )
                )
        block_rank, block_null = dependencies([(row, 0) for row in block_rows])
        block_dependencies = [selector for selector, _ in block_null]
        targets = []
        for cbit in range(12):
            kc, ic = divmod(cbit, 3)
            target = 0
            for ai in range(6):
                i, j = divmod(ai, 2)
                for bj in range(8):
                    jb, k = divmod(bj, 4)
                    if j == jb and k == kc and i == ic:
                        target |= 1 << (ai * 8 + bj)
            targets.append(target)

        full_rows = []
        for block_row_index, block_row in enumerate(block_rows):
            for cbit in range(12):
                variables = sum(
                    1 << (term * 12 + cbit)
                    for term in range(19)
                    if (block_row >> term) & 1
                )
                rhs = (targets[cbit] >> block_row_index) & 1
                full_rows.append((variables, rhs))
        full_rank, full_dependencies = dependencies(full_rows)
        assert full_rank == 12 * block_rank
        assert len(full_dependencies) == 12 * len(block_dependencies)
        block_contradictions = {
            sum(
                1 << (row * 12 + cbit)
                for row in range(48)
                if (selector >> row) & 1
            )
            for cbit, target in enumerate(targets)
            for selector in block_dependencies
            if (selector & target).bit_count() & 1
        }
        full_contradictions = {
            selector for selector, rhs in full_dependencies if rhs
        }
        assert block_contradictions == full_contradictions
        assert bool(full_contradictions) == any(
            any((selector & target).bit_count() & 1 for selector in block_dependencies)
            for target in targets
        )
        ranks[block_rank] += 1
        contradiction_counts.append(len(full_contradictions))
    print(
        f"BLOCK_EQUIVALENCE PASS models={len(models)} "
        f"block_ranks={dict(sorted(ranks.items()))} "
        f"full_rank_is_12x=PASS contradiction_sets_identical=PASS "
        f"rhs1_range={min(contradiction_counts)}..{max(contradiction_counts)}"
    )


if __name__ == "__main__":
    main()
