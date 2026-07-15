#!/usr/bin/env python3
"""Encode the rank-19 rank-one-B multiset capacity problem as OPB."""

from __future__ import annotations

import argparse
from pathlib import Path

from n324_common import rank_rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("occurrence_table", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    rank_one_b = tuple(
        value
        for value in range(1, 256)
        if rank_rows([value & 15, value >> 4], 4) == 1
    )
    assert len(rank_one_b) == 45
    index = {value: offset for offset, value in enumerate(rank_one_b)}
    rows = []
    for line in args.occurrence_table.read_text().splitlines():
        values = tuple(map(int, line.split()))
        capacity, points = values[0], values[1:]
        assert points and set(points) <= set(rank_one_b)
        rows.append((capacity, points))
    assert len(rows) == len(set(rows)) == 56724
    singleton = {
        points[0]: capacity
        for capacity, points in rows
        if len(points) == 1
    }
    assert len(singleton) == 45 and set(singleton.values()) == {2}

    def variable(value: int, copy: int) -> int:
        assert copy in (0, 1)
        return 2 * index[value] + copy + 1

    constraints = 1 + len(rank_one_b) + len(rows)
    with args.output.open("w") as out:
        out.write(
            f"* #variable= 90 #constraint= {constraints} "
            "#equal= 0 intsize= 64\n"
        )
        out.write("* xv.0/xv.1 are the first and second copies of B form v\n")
        out.write(
            " ".join(
                f"+1 x{variable(value, copy)}"
                for value in rank_one_b
                for copy in (0, 1)
            )
            + " >= 19 ;\n"
        )
        # Canonicalize two indistinguishable copies: the second implies first.
        for value in rank_one_b:
            out.write(
                f"+1 x{variable(value, 0)} -1 x{variable(value, 1)} >= 0 ;\n"
            )
        for capacity, points in rows:
            out.write(
                " ".join(
                    f"-1 x{variable(value, copy)}"
                    for value in points
                    for copy in (0, 1)
                )
                + f" >= {-capacity} ;\n"
            )
    print(
        f"rank_one_B_points={len(rank_one_b)} occurrence_rows={len(rows)} "
        f"variables=90 constraints={constraints}"
    )


if __name__ == "__main__":
    main()
