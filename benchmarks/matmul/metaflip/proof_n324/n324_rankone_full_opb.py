#!/usr/bin/env python3
"""Full exact n324 rank-19 residual in proof-producing OPB form."""

from __future__ import annotations

import argparse
from pathlib import Path

from n324_rankone_b_assignment_opb import fixed_b_orbits
from n324_common import RANK_ONE_A, rank32, rank_rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("occurrence_table", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--missing", nargs=2, type=int, required=True)
    parser.add_argument("--fixed-b", type=int, required=True)
    args = parser.parse_args()

    missing = tuple(args.missing)
    assert missing in ((1, 2), (1, 4), (1, 8))
    a = tuple(value for value in RANK_ONE_A if value not in missing)
    assert len(a) == len(set(a)) == 19
    canonical_a = {(1, 2): 3, (1, 4): 5, (1, 8): 15}[missing]
    canonical_term = a.index(canonical_a)
    b_orbits = fixed_b_orbits(missing, canonical_a)
    assert args.fixed_b in {orbit[0] for orbit in b_orbits}

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
        occurrence_rows.append((values[0], values[1:]))
    assert len(occurrence_rows) == len(set(occurrence_rows)) == 56724

    # Variable blocks: one-hot B choices, C bits, choice*C products, and four
    # parity-quotient bits for each of the 576 tensor coefficient equations.
    y_base = 1
    c_base = y_base + 19 * 45
    z_base = c_base + 19 * 12
    parity_base = z_base + 19 * 45 * 12
    variable_count = parity_base + 576 * 4 - 1
    assert variable_count == 13647

    def y(term: int, bvalue: int) -> int:
        return y_base + term * 45 + bindex[bvalue]

    def c(term: int, cbit: int) -> int:
        return c_base + term * 12 + cbit

    def z(term: int, bvalue: int, cbit: int) -> int:
        return z_base + (term * 45 + bindex[bvalue]) * 12 + cbit

    def parity(equation: int, bit: int) -> int:
        return parity_base + equation * 4 + bit

    rank_two_a = [value for value in range(1, 64) if rank32(value) == 2]
    assert len(rank_two_a) == 42
    constraint_count = (
        2 * 19
        + 19
        + 1
        + 3 * 19 * 45 * 12
        + len(occurrence_rows)
        + 42 * 255
        + 2 * 576
    )
    assert constraint_count == 99424

    with args.output.open("w") as out:
        out.write(
            f"* #variable= {variable_count} #constraint= {constraint_count} "
            "#equal= 0 intsize= 64\n"
        )
        out.write(
            f"* exact GF(2) <3,2,4> rank19; missing_A {missing}; "
            f"fixed canonical A={canonical_a} B={args.fixed_b}\n"
        )

        for term in range(19):
            choices = [y(term, value) for value in rank_one_b]
            out.write(" ".join(f"+1 x{x}" for x in choices) + " >= 1 ;\n")
            out.write(" ".join(f"-1 x{x}" for x in choices) + " >= -1 ;\n")
            out.write(
                " ".join(f"+1 x{c(term, cbit)}" for cbit in range(12))
                + " >= 1 ;\n"
            )
        out.write(f"+1 x{y(canonical_term, args.fixed_b)} >= 1 ;\n")

        for term in range(19):
            for bvalue in rank_one_b:
                for cbit in range(12):
                    product = z(term, bvalue, cbit)
                    out.write(f"+1 x{y(term, bvalue)} -1 x{product} >= 0 ;\n")
                    out.write(f"+1 x{c(term, cbit)} -1 x{product} >= 0 ;\n")
                    out.write(
                        f"-1 x{y(term, bvalue)} -1 x{c(term, cbit)} "
                        f"+1 x{product} >= -1 ;\n"
                    )

        for capacity, points in occurrence_rows:
            out.write(
                " ".join(
                    f"-1 x{y(term, value)}"
                    for term in range(19)
                    for value in points
                )
                + f" >= {-capacity} ;\n"
            )

        for functional_a in rank_two_a:
            active = [
                term
                for term, avalue in enumerate(a)
                if (functional_a & avalue).bit_count() & 1
            ]
            assert 10 <= len(active) <= 12
            for functional_b in range(1, 256):
                hits = [
                    y(term, value)
                    for term in active
                    for value in rank_one_b
                    if (functional_b & value).bit_count() & 1
                ]
                out.write(" ".join(f"+1 x{x}" for x in hits) + " >= 1 ;\n")

        equation = 0
        for ai in range(6):
            i, j = divmod(ai, 2)
            for bj in range(8):
                jb, k = divmod(bj, 4)
                for cbit in range(12):
                    kc, ic = divmod(cbit, 3)
                    rhs = int(j == jb and k == kc and i == ic)
                    products = [
                        z(term, bvalue, cbit)
                        for term, avalue in enumerate(a)
                        if (avalue >> ai) & 1
                        for bvalue in rank_one_b
                        if (bvalue >> bj) & 1
                    ]
                    quotient = [parity(equation, bit) for bit in range(4)]
                    expression = " ".join(f"+1 x{x}" for x in products)
                    expression += " " + " ".join(
                        f"-{2 << bit} x{x}" for bit, x in enumerate(quotient)
                    )
                    out.write(expression + f" >= {rhs} ;\n")
                    inverse = " ".join(f"-1 x{x}" for x in products)
                    inverse += " " + " ".join(
                        f"+{2 << bit} x{x}" for bit, x in enumerate(quotient)
                    )
                    out.write(inverse + f" >= {-rhs} ;\n")
                    equation += 1
        assert equation == 576

    print(
        f"missing={missing} fixed_B={args.fixed_b} variables={variable_count} "
        f"constraints={constraint_count} occurrence={len(occurrence_rows)}"
    )


if __name__ == "__main__":
    main()
