#!/usr/bin/env python3
"""Append an exact rank-at-most-seven quotient factorization to an n324 OPB.

For the 36-by-19 quotient matrix V selected by the one-hot B variables, this
encodes V = U L with U in F2^(36x7) and L in F2^(7x19).  Products are ordinary
Boolean AND gates; parity is represented by a two-bit nonnegative quotient.
The construction is equisatisfiable with rank(V) <= 7.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from n324_common import RANK_ONE_A
from n324_quotient_rank import factor_a, quotient_column, rank_one_b_values


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--missing", nargs=2, type=int, required=True)
    parser.add_argument(
        "--term-order",
        choices=("natural", "canonical-first", "group-x", "group-y"),
        default="natural",
        help="column order used only for the RREF symmetry break",
    )
    args = parser.parse_args()

    missing = tuple(args.missing)
    assert missing in ((1, 2), (1, 4), (1, 8))
    avalues = tuple(value for value in RANK_ONE_A if value not in missing)
    bvalues = rank_one_b_values()
    term_order = list(range(19))
    if args.term_order == "canonical-first":
        canonical = {(1, 2): 3, (1, 4): 5, (1, 8): 15}[missing]
        first = avalues.index(canonical)
        term_order = [first] + [term for term in term_order if term != first]
    elif args.term_order == "group-x":
        term_order.sort(key=lambda term: (factor_a(avalues[term]), term))
    elif args.term_order == "group-y":
        term_order.sort(
            key=lambda term: (
                factor_a(avalues[term])[1], factor_a(avalues[term])[0], term
            )
        )
    assert sorted(term_order) == list(range(19))

    with args.base.open() as source:
        header = source.readline()
        variable_match = re.search(r"#variable= (\d+)", header)
        constraint_match = re.search(r"#constraint= (\d+)", header)
        assert variable_match and constraint_match
        old_variables = int(variable_match.group(1))
        old_constraints = int(constraint_match.group(1))

    u_base = old_variables + 1
    lambda_base = u_base + 36 * 7
    product_base = lambda_base + 19 * 7
    parity_base = product_base + 19 * 36 * 7
    pivot_base = parity_base + 19 * 36 * 2
    variable_count = pivot_base + 7 * 19 - 1
    rref_constraints = (
        2 * 7
        + 6 * sum(t + 1 for t in range(19))
        + 7 * 19
        + 6 * 7 * 19
        + 7 * sum(range(19))
    )
    assert rref_constraints == 3282
    added_constraints = 3 * 19 * 36 * 7 + 2 * 19 * 36 + rref_constraints
    constraint_count = old_constraints + added_constraints

    def u(coordinate: int, basis: int) -> int:
        return u_base + coordinate * 7 + basis

    def lam(term: int, basis: int) -> int:
        return lambda_base + term * 7 + basis

    def product(term: int, coordinate: int, basis: int) -> int:
        return product_base + (term * 36 + coordinate) * 7 + basis

    def parity(term: int, coordinate: int, bit: int) -> int:
        return parity_base + (term * 36 + coordinate) * 2 + bit

    def pivot(basis: int, term: int) -> int:
        return pivot_base + basis * 19 + term

    columns = [
        [quotient_column(avalue, bvalue) for bvalue in bvalues]
        for avalue in avalues
    ]

    with args.base.open() as source, args.output.open("w") as output:
        source_header = source.readline()
        source_header = (
            source_header[:variable_match.start(1)]
            + str(variable_count)
            + source_header[variable_match.end(1):constraint_match.start(1)]
            + str(constraint_count)
            + source_header[constraint_match.end(1):]
        )
        output.write(source_header)
        for line in source:
            output.write(line)
        output.write(
            "* exact necessary condition: quotient rank <= 7; V=UL with "
            f"full-row-rank L in RREF; term_order {args.term_order} "
            + " ".join(map(str, term_order)) + "\n"
        )

        # In an exact rank-19 decomposition the quotient rank is exactly seven.
        # The factorization itself encodes rank at most seven: lower-rank row
        # spaces can be extended to a full-row-rank L, with a deficient U.
        # Putting L in RREF removes the full GL(7,2) gauge.
        for basis in range(7):
            choices = [pivot(basis, term) for term in range(19)]
            output.write(" ".join(f"+1 x{x}" for x in choices) + " >= 1 ;\n")
            output.write(" ".join(f"-1 x{x}" for x in choices) + " >= -1 ;\n")
        for basis in range(6):
            for term in range(19):
                for next_term in range(term + 1):
                    output.write(
                        f"-1 x{pivot(basis, term)} "
                        f"-1 x{pivot(basis + 1, next_term)} >= -1 ;\n"
                    )
        for basis in range(7):
            for position, term in enumerate(term_order):
                p = pivot(basis, position)
                output.write(f"-1 x{p} +1 x{lam(term, basis)} >= 0 ;\n")
                for other_basis in range(7):
                    if other_basis != basis:
                        output.write(
                            f"-1 x{p} -1 x{lam(term, other_basis)} >= -1 ;\n"
                        )
                for earlier_position in range(position):
                    earlier_term = term_order[earlier_position]
                    output.write(
                        f"-1 x{p} -1 x{lam(earlier_term, basis)} >= -1 ;\n"
                    )

        for term in range(19):
            for coordinate in range(36):
                for basis in range(7):
                    w = product(term, coordinate, basis)
                    output.write(f"+1 x{u(coordinate, basis)} -1 x{w} >= 0 ;\n")
                    output.write(f"+1 x{lam(term, basis)} -1 x{w} >= 0 ;\n")
                    output.write(
                        f"-1 x{u(coordinate, basis)} -1 x{lam(term, basis)} "
                        f"+1 x{w} >= -1 ;\n"
                    )

                # The one-hot sum below is exactly the selected quotient bit.
                products = " ".join(
                    f"+1 x{product(term, coordinate, basis)}"
                    for basis in range(7)
                )
                selected = " ".join(
                    f"-1 x{term * 45 + offset + 1}"
                    for offset, column in enumerate(columns[term])
                    if (column >> coordinate) & 1
                )
                quotients = (
                    f"-2 x{parity(term, coordinate, 0)} "
                    f"-4 x{parity(term, coordinate, 1)}"
                )
                expression = f"{products} {selected} {quotients}"
                output.write(expression + " >= 0 ;\n")
                inverse_products = " ".join(
                    f"-1 x{product(term, coordinate, basis)}"
                    for basis in range(7)
                )
                inverse_selected = " ".join(
                    f"+1 x{term * 45 + offset + 1}"
                    for offset, column in enumerate(columns[term])
                    if (column >> coordinate) & 1
                )
                inverse_quotients = (
                    f"+2 x{parity(term, coordinate, 0)} "
                    f"+4 x{parity(term, coordinate, 1)}"
                )
                output.write(
                    f"{inverse_products} {inverse_selected} "
                    f"{inverse_quotients} >= 0 ;\n"
                )

    print(
        f"missing={missing} old_variables={old_variables} "
        f"variables={variable_count} added_constraints={added_constraints} "
        f"constraints={constraint_count} term_order={args.term_order}"
    )


if __name__ == "__main__":
    main()
