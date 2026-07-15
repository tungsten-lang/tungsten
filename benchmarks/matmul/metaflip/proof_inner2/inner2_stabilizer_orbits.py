#!/usr/bin/env python3
"""Residual fixed-term orbits for GF(2) ``<a,2,c>`` decompositions.

After the adjacent factors of one term have been put in one of the five
rank/pairing normal forms, their stabilizer still acts on the third factor.
This module constructs a small generating set for that stabilizer and exactly
enumerates its nonzero orbits.  The result gives a finite, exhaustive second
level of SAT shards.

Matrices use row-major bit masks.  The normal forms are

    A : a x 2,  rank alpha, first alpha diagonal entries one;
    B : 2 x c,  rank beta,  first beta diagonal entries one,

except that the rank-one/rank-one pairing-zero form has B[1,0] = 1.

For invertible N, G, and L satisfying

    N A = A G,             B L = G^-1 B,

the matrix-multiplication isotropy fixes A and B and sends the third factor to
``C -> L C N``.  The generators below span every such transformation: the
G=I kernels are elementary parabolic generators, and one or two elementary
generators span the allowed subgroup of GL(2,2).
"""

from __future__ import annotations

import argparse
import hashlib
import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path


@dataclass(frozen=True)
class Generator:
    name: str
    # Right operation (source column, destination column): dst ^= src.
    right: tuple[int, int] | None = None
    # Left operation (destination row, source row): dst ^= src.
    left: tuple[int, int] | None = None
    # G is I, the upper transvection, or the lower transvection.
    shared: str = "identity"


@dataclass(frozen=True)
class Orbit:
    representative: int
    size: int


CASES: tuple[tuple[str, int, int, int | None], ...] = (
    ("a1_b1_p0", 1, 1, 0),
    ("a1_b1_p1", 1, 1, 1),
    ("a1_b2", 1, 2, None),
    ("a2_b1", 2, 1, None),
    ("a2_b2", 2, 2, None),
)


def validate_case(a_rank: int, b_rank: int, pairing: int | None) -> None:
    assert a_rank in (1, 2) and b_rank in (1, 2)
    if a_rank == b_rank == 1:
        assert pairing in (0, 1)
    else:
        assert pairing is None


def generators(
    a: int, c: int, a_rank: int, b_rank: int, pairing: int | None
) -> tuple[Generator, ...]:
    """Return elementary generators of the exact A/B stabilizer action."""

    assert a >= 2 and c >= 2
    validate_case(a_rank, b_rank, pairing)
    result: list[Generator] = []

    # N A=A: GL on the complement of im(A), plus the upper-right block.
    for coordinate in range(a_rank, a - 1):
        result.append(
            Generator(
                f"N complement {coordinate}->{coordinate + 1}",
                right=(coordinate, coordinate + 1),
            )
        )
        result.append(
            Generator(
                f"N complement {coordinate + 1}->{coordinate}",
                right=(coordinate + 1, coordinate),
            )
        )
    for source in range(a_rank):
        for destination in range(a_rank, a):
            result.append(
                Generator(
                    f"N fringe {source}->{destination}",
                    right=(source, destination),
                )
            )

    # B L=B: GL on ker(B), plus the lower-left block.
    for coordinate in range(b_rank, c - 1):
        result.append(
            Generator(
                f"L complement {coordinate + 1}->{coordinate}",
                left=(coordinate, coordinate + 1),
            )
        )
        result.append(
            Generator(
                f"L complement {coordinate}->{coordinate + 1}",
                left=(coordinate + 1, coordinate),
            )
        )
    for destination in range(b_rank, c):
        for source in range(b_rank):
            result.append(
                Generator(
                    f"L fringe {source}->{destination}",
                    left=(destination, source),
                )
            )

    # Allowed G must preserve ker(A) when A has rank one and im(B) when B
    # has rank one.  Over F2 this leaves the cases below.
    shared: tuple[str, ...]
    if a_rank == b_rank == 2:
        shared = ("upper", "lower")
    elif a_rank == 1 and b_rank == 2:
        shared = ("lower",)
    elif a_rank == 2 and b_rank == 1:
        shared = ("upper",)
    elif pairing == 0:
        shared = ("lower",)
    else:
        shared = ()

    for kind in shared:
        operation = (0, 1) if kind == "upper" else (1, 0)
        right = operation if a_rank == 2 else None
        left = operation if b_rank == 2 else None
        if right is not None or left is not None:
            result.append(
                Generator(
                    f"G {kind}",
                    right=right,
                    left=left,
                    shared=kind,
                )
            )
    return tuple(result)


def _shift(value: int, distance: int) -> int:
    return value << distance if distance >= 0 else value >> -distance


@lru_cache(maxsize=None)
def _column_mask(a: int, c: int, column: int) -> int:
    return sum(1 << (row * a + column) for row in range(c))


def apply_generator(value: int, a: int, c: int, generator: Generator) -> int:
    """Apply one ``C -> L C N`` generator to a row-major C mask."""

    if generator.right is not None:
        source, destination = generator.right
        source_mask = _column_mask(a, c, source)
        value ^= _shift(value & source_mask, destination - source)
    if generator.left is not None:
        destination, source = generator.left
        row_mask = (1 << a) - 1
        source_value = (value >> (source * a)) & row_mask
        value ^= source_value << (destination * a)
    return value


def enumerate_orbits(
    a: int, c: int, a_rank: int, b_rank: int, pairing: int | None
) -> tuple[Orbit, ...]:
    """Enumerate every nonzero C orbit, with the least mask as representative."""

    actions = generators(a, c, a_rank, b_rank, pairing)
    limit = 1 << (a * c)
    seen = bytearray(limit)
    result: list[Orbit] = []
    for root in range(1, limit):
        if seen[root]:
            continue
        seen[root] = 1
        queue = [root]
        cursor = 0
        while cursor < len(queue):
            value = queue[cursor]
            cursor += 1
            for action in actions:
                neighbor = apply_generator(value, a, c, action)
                if not seen[neighbor]:
                    seen[neighbor] = 1
                    queue.append(neighbor)
        result.append(Orbit(root, len(queue)))
    assert sum(orbit.size for orbit in result) == limit - 1
    return tuple(result)


def orbit_digest(orbits: tuple[Orbit, ...]) -> str:
    payload = "".join(
        f"{orbit.representative}:{orbit.size}\n" for orbit in orbits
    ).encode()
    return hashlib.sha256(payload).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--a", type=int, required=True)
    parser.add_argument("--c", type=int, required=True)
    parser.add_argument("--a-rank", type=int, choices=(1, 2), required=True)
    parser.add_argument("--b-rank", type=int, choices=(1, 2), required=True)
    parser.add_argument("--pairing", type=int, choices=(0, 1))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    found = enumerate_orbits(
        args.a, args.c, args.a_rank, args.b_rank, args.pairing
    )
    data = {
        "a": args.a,
        "c": args.c,
        "a_rank": args.a_rank,
        "b_rank": args.b_rank,
        "pairing": args.pairing if args.pairing is not None else "na",
        "generators": len(
            generators(args.a, args.c, args.a_rank, args.b_rank, args.pairing)
        ),
        "orbit_count": len(found),
        "covered_nonzero_c": sum(orbit.size for orbit in found),
        "digest": orbit_digest(found),
        "orbits": [
            {"representative": orbit.representative, "size": orbit.size}
            for orbit in found
        ],
    }
    text = json.dumps(data, indent=2, sort_keys=True) + "\n"
    if args.output is None:
        print(text, end="")
    else:
        args.output.write_text(text)


if __name__ == "__main__":
    main()
