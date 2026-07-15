#!/usr/bin/env python3
"""Independent planted audit of the quotient-rank RREF OPB encoding.

This does not import the production encoder.  It instantiates the same
rank-at-most-seven construction on fixed 8-by-9 matrices of every rank zero
through eight, under both natural and reversed column orders.  Ranks 0..7
must be SAT and rank 8 must be UNSAT.
"""

from __future__ import annotations

import argparse
import subprocess
import tempfile
from pathlib import Path


ROWS = 8
COLS = 9
CAP = 7


def planted_columns(rank: int) -> tuple[int, ...]:
    assert 0 <= rank <= 8
    columns = [1 << index for index in range(rank)]
    while len(columns) < COLS:
        value = 0
        for index in range(rank):
            if ((len(columns) + 3 * index + rank) % 5) < 2:
                value ^= 1 << index
        columns.append(value)
    return tuple(columns)


def write_encoding(path: Path, columns: tuple[int, ...], order: tuple[int, ...]) -> None:
    assert len(columns) == COLS and sorted(order) == list(range(COLS))
    u_base = 1
    lambda_base = u_base + ROWS * CAP
    product_base = lambda_base + COLS * CAP
    parity_base = product_base + COLS * ROWS * CAP
    pivot_base = parity_base + COLS * ROWS * 2
    variables = pivot_base + CAP * COLS - 1
    rref_constraints = (
        2 * CAP
        + (CAP - 1) * sum(position + 1 for position in range(COLS))
        + CAP * COLS
        + (CAP - 1) * CAP * COLS
        + CAP * sum(range(COLS))
    )
    constraints = 3 * COLS * ROWS * CAP + 2 * COLS * ROWS + rref_constraints

    def u(row: int, basis: int) -> int:
        return u_base + row * CAP + basis

    def lam(column: int, basis: int) -> int:
        return lambda_base + column * CAP + basis

    def product(column: int, row: int, basis: int) -> int:
        return product_base + (column * ROWS + row) * CAP + basis

    def parity(column: int, row: int, bit: int) -> int:
        return parity_base + (column * ROWS + row) * 2 + bit

    def pivot(basis: int, position: int) -> int:
        return pivot_base + basis * COLS + position

    with path.open("w") as out:
        out.write(
            f"* #variable= {variables} #constraint= {constraints} "
            "#equal= 0 intsize= 64\n"
        )
        for basis in range(CAP):
            choices = [pivot(basis, position) for position in range(COLS)]
            out.write(" ".join(f"+1 x{x}" for x in choices) + " >= 1 ;\n")
            out.write(" ".join(f"-1 x{x}" for x in choices) + " >= -1 ;\n")
        for basis in range(CAP - 1):
            for position in range(COLS):
                for next_position in range(position + 1):
                    out.write(
                        f"-1 x{pivot(basis, position)} "
                        f"-1 x{pivot(basis + 1, next_position)} >= -1 ;\n"
                    )
        for basis in range(CAP):
            for position, column in enumerate(order):
                p = pivot(basis, position)
                out.write(f"-1 x{p} +1 x{lam(column, basis)} >= 0 ;\n")
                for other in range(CAP):
                    if other != basis:
                        out.write(
                            f"-1 x{p} -1 x{lam(column, other)} >= -1 ;\n"
                        )
                for earlier in range(position):
                    out.write(
                        f"-1 x{p} -1 x{lam(order[earlier], basis)} >= -1 ;\n"
                    )

        for column in range(COLS):
            for row in range(ROWS):
                for basis in range(CAP):
                    w = product(column, row, basis)
                    out.write(f"+1 x{u(row, basis)} -1 x{w} >= 0 ;\n")
                    out.write(f"+1 x{lam(column, basis)} -1 x{w} >= 0 ;\n")
                    out.write(
                        f"-1 x{u(row, basis)} -1 x{lam(column, basis)} "
                        f"+1 x{w} >= -1 ;\n"
                    )
                products = " ".join(
                    f"+1 x{product(column, row, basis)}"
                    for basis in range(CAP)
                )
                quotients = (
                    f"-2 x{parity(column, row, 0)} "
                    f"-4 x{parity(column, row, 1)}"
                )
                bit = (columns[column] >> row) & 1
                out.write(f"{products} {quotients} >= {bit} ;\n")
                inverse_products = " ".join(
                    f"-1 x{product(column, row, basis)}"
                    for basis in range(CAP)
                )
                inverse_quotients = (
                    f"+2 x{parity(column, row, 0)} "
                    f"+4 x{parity(column, row, 1)}"
                )
                out.write(
                    f"{inverse_products} {inverse_quotients} >= {-bit} ;\n"
                )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--solver", type=Path, required=True)
    args = parser.parse_args()
    assert args.solver.is_file()
    cases = 0
    with tempfile.TemporaryDirectory(prefix="n324-qrank-audit-") as temporary:
        temporary = Path(temporary)
        for rank in range(9):
            for label, order in (
                ("natural", tuple(range(COLS))),
                ("reversed", tuple(reversed(range(COLS)))),
            ):
                formula = temporary / f"rank{rank}_{label}.opb"
                write_encoding(formula, planted_columns(rank), order)
                result = subprocess.run(
                    [
                        str(args.solver), "--verbosity=0", "--print-sol=0",
                        "--time-limit=30", str(formula),
                    ],
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    check=True,
                )
                expected = "SATISFIABLE" if rank <= CAP else "UNSATISFIABLE"
                assert f"s {expected}" in result.stdout, (rank, label, result.stdout)
                cases += 1
                print(f"rank={rank} order={label} result={expected}")
    print(f"QUOTIENT_ENCODING_AUDIT PASS cases={cases} ranks=0..8 orders=2")


if __name__ == "__main__":
    main()
