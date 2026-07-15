#!/usr/bin/env python3
"""Audit and symmetry-shard the n243 rank-two capacity instance."""

from __future__ import annotations

import argparse
from pathlib import Path


BASE = 18
Q_BITS = (0, 1, 2, 3, 5, 6, 7)


def rank(mask: int, rows: int, cols: int) -> int:
    matrix = [
        (mask >> (row * cols)) & ((1 << cols) - 1) for row in range(rows)
    ]
    out = 0
    for col in range(cols):
        pivot = next(
            (row for row in range(out, rows) if (matrix[row] >> col) & 1), None
        )
        if pivot is None:
            continue
        matrix[out], matrix[pivot] = matrix[pivot], matrix[out]
        for row in range(rows):
            if row != out and ((matrix[row] >> col) & 1):
                matrix[row] ^= matrix[out]
        out += 1
    return out


def matrices(n: int) -> list[int]:
    return [mask for mask in range(1 << (n * n)) if rank(mask, n, n) == n]


def mul(a: int, ar: int, ac: int, b: int, bc: int) -> int:
    out = 0
    for row in range(ar):
        for col in range(bc):
            bit = 0
            for inner in range(ac):
                bit ^= ((a >> (row * ac + inner)) & 1) & (
                    (b >> (inner * bc + col)) & 1
                )
            out |= bit << (row * bc + col)
    return out


def apply(left: int, right: int, value: int) -> int:
    return mul(mul(left, 2, 2, value, 4), 2, 4, right, 4)


def lift(point: int) -> int:
    return sum(((point >> i) & 1) << bit for i, bit in enumerate(Q_BITS))


def quotient(value: int) -> int:
    if (value >> 4) & 1:
        value ^= BASE
    assert not ((value >> 4) & 1)
    return sum(((value >> bit) & 1) << i for i, bit in enumerate(Q_BITS))


def permutations() -> list[tuple[int, ...]]:
    gl2, gl4 = matrices(2), matrices(4)
    assert len(gl2) == 6 and len(gl4) == 20160
    result = []
    for left in gl2:
        for right in gl4:
            if apply(left, right, BASE) != BASE:
                continue
            permutation = tuple(
                [0]
                + [quotient(apply(left, right, lift(x))) for x in range(1, 128)]
            )
            assert sorted(permutation) == list(range(128))
            result.append(permutation)
    assert len(result) == 576
    assert len(set(result)) == 576
    return result


def point_orbits(permutations_: list[tuple[int, ...]]) -> list[tuple[int, ...]]:
    unseen = set(range(1, 128))
    result = []
    while unseen:
        seed = min(unseen)
        orbit = tuple(sorted({permutation[seed] for permutation in permutations_}))
        assert set(orbit) <= unseen
        unseen -= set(orbit)
        result.append(orbit)
    return result


def read_table(path: Path) -> list[tuple[int, tuple[int, ...]]]:
    rows = []
    for line in path.read_text().splitlines():
        values = tuple(map(int, line.split()))
        rows.append((values[0], values[1:]))
    return rows


def audit(
    rows: list[tuple[int, tuple[int, ...]]],
    permutations_: list[tuple[int, ...]],
) -> None:
    keyed = {(capacity, points) for capacity, points in rows}
    assert len(keyed) == len(rows)
    for index, permutation in enumerate(permutations_):
        for capacity, points in rows:
            image = tuple(sorted(permutation[x] for x in points))
            assert (capacity, image) in keyed, (index, capacity, points, image)


def write_opb(
    path: Path,
    rows: list[tuple[int, tuple[int, ...]]],
    zeros: list[int],
    ones: list[int],
) -> None:
    with path.open("w") as out:
        # Current RoundingSat proof logging requires the extended OPB header.
        out.write(
            f"* #variable= 127 #constraint= {len(rows) + 1 + len(zeros) + len(ones)} "
            "#equal= 0 intsize= 64\n"
        )
        for capacity, points in rows:
            out.write(" ".join(f"-1 x{x}" for x in points))
            out.write(f" >= {-capacity} ;\n")
        out.write(" ".join(f"+1 x{x}" for x in range(1, 128)))
        out.write(" >= 18 ;\n")
        for point in zeros:
            out.write(f"-1 x{point} >= 0 ;\n")
        for point in ones:
            out.write(f"+1 x{point} >= 1 ;\n")


def emit_opb(
    rows: list[tuple[int, tuple[int, ...]]],
    orbits: list[tuple[int, ...]],
    permutations_: list[tuple[int, ...]],
    out_dir: Path,
) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    prior: list[int] = []
    for index, orbit in enumerate(orbits):
        representative = orbit[0]
        path = out_dir / (
            f"n243_capacity_orbit_{index:02d}_rep_{representative:03d}.opb"
        )
        write_opb(path, rows, prior, [representative])

        # Partition the two hard roots under their fixed-point stabilizers.
        if index < 2:
            subgroup = [
                permutation
                for permutation in permutations_
                if permutation[representative] == representative
            ]
            allowed = set(range(1, 128)) - set(prior) - {representative}
            suborbits = []
            while allowed:
                seed = min(allowed)
                suborbit = tuple(sorted({permutation[seed] for permutation in subgroup}))
                assert set(suborbit) <= allowed
                allowed -= set(suborbit)
                suborbits.append(suborbit)
            suborbits.sort(key=lambda child: (-len(child), child[0]))
            print(
                f"root {index}: stabilizer={len(subgroup)} child_orbits="
                f"{[(len(child), child[0]) for child in suborbits]}"
            )
            subprior: list[int] = []
            for subindex, suborbit in enumerate(suborbits):
                subrepresentative = suborbit[0]
                subpath = out_dir / (
                    f"n243_capacity_orbit_{index:02d}_rep_{representative:03d}"
                    f"_child_{subindex:02d}_rep_{subrepresentative:03d}.opb"
                )
                write_opb(
                    subpath,
                    rows,
                    prior + subprior,
                    [representative, subrepresentative],
                )
                subprior.extend(suborbit)
        prior.extend(orbit)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("table", type=Path)
    parser.add_argument("out_dir", type=Path)
    parser.add_argument("--skip-audit", action="store_true")
    args = parser.parse_args()
    rows = read_table(args.table)
    permutations_ = permutations()
    # A shard fixes the first occupied orbit representative and zeros all
    # earlier orbits, making the cases disjoint and exhaustive for |X| >= 18.
    orbits = sorted(
        point_orbits(permutations_), key=lambda orbit: (-len(orbit), orbit[0])
    )
    if not args.skip_audit:
        audit(rows, permutations_)
    print(f"group={len(permutations_)} point_orbits={len(orbits)}")
    for index, orbit in enumerate(orbits):
        print(
            f"orbit {index}: size={len(orbit)} rep={orbit[0]} "
            f"points={' '.join(map(str, orbit))}"
        )
    emit_opb(rows, orbits, permutations_, args.out_dir)


if __name__ == "__main__":
    main()
