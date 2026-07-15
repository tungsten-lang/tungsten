#!/usr/bin/env python3
"""Necessary rank-one-B assignment problem for a fixed n324 A support."""

from __future__ import annotations

import argparse
from pathlib import Path

from fixed_a_shards import left_b
from n324_common import (
    RANK_ONE_A,
    apply_a,
    gl_packed,
    inverse_square,
    rank32,
    rank_rows,
)


def fixed_b_orbits(
    missing: tuple[int, int], canonical_a: int
) -> list[tuple[int, ...]]:
    """Re-derive B orbits at a fixed A term under the A-support stabilizer."""
    action = []
    for left in gl_packed(3):
        for right in gl_packed(2):
            if {apply_a(value, left, right) for value in missing} != set(missing):
                continue
            if apply_a(canonical_a, left, right) != canonical_a:
                continue
            action.append(inverse_square(right, 2))
    expected_size = {(1, 2): 48, (1, 4): 16, (1, 8): 8}[missing]
    assert len(action) == expected_size
    # GL(4,2) is transitive on the nonzero q in B=p*q^T, so q can first be
    # normalized to 1.  The remaining orbit question is the action on p.
    row_types = {1, 16, 17}
    unseen = set(row_types)
    orbits = []
    while unseen:
        seed = min(unseen)
        orbit = tuple(sorted({left_b(right_inverse, seed) for right_inverse in action}))
        assert set(orbit) <= row_types
        unseen -= set(orbit)
        orbits.append(orbit)
    return orbits


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("occurrence_table", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--missing", nargs=2, type=int, required=True)
    parser.add_argument("--fixed-b", type=int)
    parser.add_argument(
        "--skip-occurrence",
        action="store_true",
        help="omit certified occurrence rows (useful for testing weaker cores)",
    )
    args = parser.parse_args()

    missing = tuple(args.missing)
    assert missing in ((1, 2), (1, 4), (1, 8))
    a = tuple(value for value in RANK_ONE_A if value not in missing)
    assert len(a) == len(set(a)) == 19
    canonical_a = {(1, 2): 3, (1, 4): 5, (1, 8): 15}[missing]
    canonical_term = a.index(canonical_a)
    b_orbits = fixed_b_orbits(missing, canonical_a)
    rank_one_b = tuple(
        value
        for value in range(1, 256)
        if rank_rows([value & 15, value >> 4], 4) == 1
    )
    assert len(rank_one_b) == 45
    bindex = {value: index for index, value in enumerate(rank_one_b)}

    occurrence_rows = []
    for line in args.occurrence_table.read_text().splitlines():
        values = tuple(map(int, line.split()))
        capacity, points = values[0], values[1:]
        assert points and set(points) <= set(rank_one_b)
        occurrence_rows.append((capacity, points))
    assert len(occurrence_rows) == len(set(occurrence_rows)) == 56724

    def variable(term: int, bvalue: int) -> int:
        return term * 45 + bindex[bvalue] + 1

    rank_two_a = [value for value in range(1, 64) if rank32(value) == 2]
    assert len(rank_two_a) == 42
    span_constraints = len(rank_two_a) * 255
    fixed_constraints = int(args.fixed_b is not None)
    if args.fixed_b is not None:
        representatives = {orbit[0] for orbit in b_orbits}
        assert args.fixed_b in representatives, (args.fixed_b, representatives)
    included_occurrence = 0 if args.skip_occurrence else len(occurrence_rows)
    constraint_count = 2 * 19 + included_occurrence + span_constraints + fixed_constraints
    with args.output.open("w") as out:
        out.write(
            f"* #variable= 855 #constraint= {constraint_count} "
            "#equal= 0 intsize= 64\n"
        )
        out.write(
            f"* missing_A {missing[0]} {missing[1]}; "
            f"A_support {' '.join(map(str, a))}\n"
        )
        out.write("* xt.v means term t has rank-one B form v\n")
        out.write(
            f"* canonical_A_term {canonical_term} A {canonical_a}; "
            f"fixed_B_orbits {b_orbits}\n"
        )

        # Exactly one of the 45 rank-one B forms is assigned to each term.
        for term in range(19):
            variables = [variable(term, value) for value in rank_one_b]
            out.write(" ".join(f"+1 x{x}" for x in variables) + " >= 1 ;\n")
            out.write(" ".join(f"-1 x{x}" for x in variables) + " >= -1 ;\n")

        if args.fixed_b is not None:
            out.write(f"+1 x{variable(canonical_term, args.fixed_b)} >= 1 ;\n")

        # Certified occurrence lemma for every B subspace represented by its
        # intersection with the 45 allowed rank-one forms.
        if not args.skip_occurrence:
            for capacity, points in occurrence_rows:
                out.write(
                    " ".join(
                        f"-1 x{variable(term, value)}"
                        for term in range(19)
                        for value in points
                    )
                    + f" >= {-capacity} ;\n"
                )

        # Contracting A by a rank-two functional yields a B-by-C matrix of row
        # rank eight.  Therefore the active B factors span all of F2^8.  The
        # following clauses exclude every nonzero annihilating functional.
        for functional_a in rank_two_a:
            active = [
                term
                for term, avalue in enumerate(a)
                if (functional_a & avalue).bit_count() & 1
            ]
            assert 10 <= len(active) <= 12
            for functional_b in range(1, 256):
                hits = [
                    variable(term, value)
                    for term in active
                    for value in rank_one_b
                    if (functional_b & value).bit_count() & 1
                ]
                assert hits
                out.write(" ".join(f"+1 x{x}" for x in hits) + " >= 1 ;\n")

    print(
        f"missing={missing} fixed_B_orbits={b_orbits} fixed_B={args.fixed_b} "
        f"variables=855 constraints={constraint_count} "
        f"occurrence={included_occurrence} span={span_constraints}"
    )


if __name__ == "__main__":
    main()
