#!/usr/bin/env python3
"""Independent audit of the six fixed-B-orbit PB shards."""

from __future__ import annotations

from n324_common import (
    RANK_ONE_A,
    apply_a,
    gl_packed,
    inverse_square,
    rank_rows,
    row_times,
)


def left_b(transform: int, value: int) -> int:
    rows = (value & 15, value >> 4)
    out = 0
    for row in range(2):
        selector = (transform >> (2 * row)) & 3
        image = 0
        for inner in range(2):
            if (selector >> inner) & 1:
                image ^= rows[inner]
        out |= image << (4 * row)
    return out


def right_b(value: int, transform: int) -> int:
    return row_times(value & 15, transform, 4) | (
        row_times(value >> 4, transform, 4) << 4
    )


def main() -> None:
    rank_one_b = {
        value
        for value in range(1, 256)
        if rank_rows([value & 15, value >> 4], 4) == 1
    }
    assert len(rank_one_b) == 45
    gl3, gl2, gl4 = gl_packed(3), gl_packed(2), gl_packed(4)
    cases = {
        ((1, 2), 3): (1, 17),
        ((1, 4), 5): (1, 16),
        ((1, 8), 15): (1, 17),
    }
    expected_k_sizes = {(1, 2): 48, (1, 4): 16, (1, 8): 8}
    for (missing, canonical_a), representatives in cases.items():
        inverses = []
        for left in gl3:
            for right in gl2:
                if {apply_a(value, left, right) for value in missing} != set(
                    missing
                ):
                    continue
                if apply_a(canonical_a, left, right) != canonical_a:
                    continue
                inverses.append(inverse_square(right, 2))
        assert len(inverses) == expected_k_sizes[missing]

        orbits = []
        for representative in representatives:
            orbit = {
                right_b(left_b(right_inverse, representative), shared)
                for right_inverse in inverses
                for shared in gl4
            }
            assert orbit <= rank_one_b
            orbits.append(orbit)
        assert not orbits[0].intersection(orbits[1])
        assert orbits[0] | orbits[1] == rank_one_b
        sizes = tuple(map(len, orbits))
        assert sorted(sizes) == [15, 30]
        a_support = set(RANK_ONE_A) - set(missing)
        assert len(a_support) == 19 and canonical_a in a_support
        print(
            f"missing={missing} canonical_A={canonical_a} "
            f"K={len(inverses)} representatives={representatives} "
            f"orbit_sizes={sizes} coverage=45 disjoint=PASS"
        )


if __name__ == "__main__":
    main()
