#!/usr/bin/env python3
"""Native-XOR exact GF(2) ``<a,2,c>`` rank encoding.

This is the same exact A/B-span formulation as ``inner2_direct_rank_opb.py``.
AND gates are ordinary CNF and the tensor equations remain native XOR
constraints for CryptoMiniSat.  ``--quotient-rank`` adds the redundant
quotient factorization and its exact RREF gauge.  The same five fixed-term
rank/pairing shards form an exhaustive cover.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from itertools import combinations
from pathlib import Path
from typing import Callable

from inner2_direct_rank_opb import representative


class Xnf:
    def __init__(self) -> None:
        self.variables = 0
        self.clauses: list[list[int]] = []
        self.xors: list[tuple[list[int], int]] = []

    def block(self, size: int) -> int:
        base = self.variables + 1
        self.variables += size
        return base

    def clause(self, *literals: int) -> None:
        assert literals
        self.clauses.append(list(literals))

    def xor(self, literals: list[int], rhs: int) -> None:
        assert literals and rhs in (0, 1)
        self.xors.append((literals, rhs))

    def and_gate(self, out: int, left: int, right: int) -> None:
        self.clause(-out, left)
        self.clause(-out, right)
        self.clause(out, -left, -right)

    def not_equal(self, left: list[int], right: list[int]) -> None:
        """Require two equal-width bit vectors to differ somewhere."""
        assert left and len(left) == len(right)
        differences = []
        for x, y in zip(left, right):
            difference = self.block(1)
            # difference <-> (x XOR y), kept in ordinary CNF so thousands of
            # small pair-distinctness helpers do not pollute the Gaussian
            # matrices reserved for the tensor equations.
            self.clause(x, y, -difference)
            self.clause(-x, -y, -difference)
            self.clause(-x, y, difference)
            self.clause(x, -y, difference)
            differences.append(difference)
        self.clause(*differences)

    def lex_leq(self, left: list[int], right: list[int]) -> None:
        """Constrain equal-width bit vectors to ``left <=lex right``.

        Coordinate zero is the most significant coordinate and ``0 < 1``.
        Prefix variables record equality through each coordinate.  Keeping
        the complete equivalence, rather than one-way helper implications,
        makes this safe for propagation in either direction.
        """
        assert left and len(left) == len(right)
        prefix_base = self.block(len(left))
        previous = 0
        for coordinate, (x, y) in enumerate(zip(left, right)):
            current = prefix_base + coordinate
            if coordinate == 0:
                # At the first unequal coordinate, 1/0 is forbidden.
                self.clause(-x, y)
                # current <-> (x == y)
                self.clause(-current, -x, y)
                self.clause(-current, x, -y)
                self.clause(current, x, y)
                self.clause(current, -x, -y)
            else:
                # Ordering matters only while all earlier bits are equal.
                self.clause(-previous, -x, y)
                # current <-> previous AND (x == y)
                self.clause(-current, previous)
                self.clause(-current, -x, y)
                self.clause(-current, x, -y)
                self.clause(-previous, -x, -y, current)
                self.clause(-previous, x, y, current)
            previous = current

    def write(self, output: Path, comments: list[str]) -> None:
        lines = [f"c {comment}" for comment in comments]
        lines.append(f"p cnf {self.variables} {len(self.clauses) + len(self.xors)}")
        lines.extend(" ".join(map(str, clause)) + " 0" for clause in self.clauses)
        for literals, rhs in self.xors:
            shown = literals if rhs else [-literals[0], *literals[1:]]
            lines.append("x " + " ".join(map(str, shown)) + " 0")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text("\n".join(lines) + "\n")


def build(
    output: Path,
    a: int,
    c: int,
    terms: int,
    a_rank: int,
    b_rank: int,
    pairing: int | None,
    fixed_c: int | None = None,
    quotient_rank: bool = False,
    rref: bool = True,
    lex_terms: bool = False,
    nonzero_c: bool = False,
    minimal_terms: bool = False,
    dual_inner2_quotient: bool = False,
    span_dependency_weight: int = 0,
) -> dict[str, int | str | bool]:
    assert a >= 2 and c >= 2 and terms >= 1
    assert a_rank in (1, 2) and b_rank in (1, 2)
    if a_rank == b_rank == 1:
        assert pairing in (0, 1)
    else:
        assert pairing is None

    adim, bdim, targets = 2 * a, 2 * c, a * c
    assert 0 <= span_dependency_weight <= max(adim, bdim, targets)
    if fixed_c is not None:
        assert 0 < fixed_c < (1 << targets)
    ambient = adim * bdim
    quotient_coordinates = 3 * targets
    cap = terms - targets
    if quotient_rank:
        assert cap >= 0, "rank is already below the C flattening bound a*c"
    if dual_inner2_quotient:
        assert c == 2, "the dual inner-2 quotient requires <a,2,2> orientation"
        assert terms >= adim, "rank is already below the A flattening bound 2*a"
    xnf = Xnf()
    a_base = xnf.block(terms * adim)
    b_base = xnf.block(terms * bdim)
    product_base = xnf.block(terms * ambient)
    coefficient_base = xnf.block(terms * targets)
    expansion_base = xnf.block(terms * ambient * targets)
    nonvacuous_quotient = quotient_rank and cap < min(quotient_coordinates, terms)
    quotient_xor_base = xnf.block(terms * targets) if nonvacuous_quotient else 0
    u_base = xnf.block(quotient_coordinates * cap) if nonvacuous_quotient else 0
    lam_base = xnf.block(terms * cap) if nonvacuous_quotient else 0
    ul_product_base = (
        xnf.block(terms * quotient_coordinates * cap)
        if nonvacuous_quotient else 0
    )
    pivot_base = xnf.block(cap * terms) if nonvacuous_quotient and rref else 0

    # In the cyclic <a,2,2> orientation, B tensor C also contracts through an
    # inner dimension two.  Its quotient condition is independent of the
    # A tensor B condition above and has the same 3*(2a) by terms shape.
    dual_cap = terms - adim
    dual_coordinates = 3 * adim
    nonvacuous_dual = (
        dual_inner2_quotient and dual_cap < min(dual_coordinates, terms)
    )
    bc_product_base = (
        xnf.block(terms * bdim * targets) if nonvacuous_dual else 0
    )
    dual_xor_base = xnf.block(terms * adim) if nonvacuous_dual else 0
    dual_u_base = (
        xnf.block(dual_coordinates * dual_cap) if nonvacuous_dual else 0
    )
    dual_lam_base = xnf.block(terms * dual_cap) if nonvacuous_dual else 0
    dual_ul_product_base = (
        xnf.block(terms * dual_coordinates * dual_cap)
        if nonvacuous_dual else 0
    )
    dual_pivot_base = (
        xnf.block(dual_cap * terms) if nonvacuous_dual and rref else 0
    )

    def avar(term: int, coordinate: int) -> int:
        return a_base + term * adim + coordinate

    def bvar(term: int, coordinate: int) -> int:
        return b_base + term * bdim + coordinate

    def product(term: int, ai: int, bi: int) -> int:
        return product_base + (term * adim + ai) * bdim + bi

    def coefficient(term: int, target: int) -> int:
        return coefficient_base + term * targets + target

    def expansion(term: int, coordinate: int, target: int) -> int:
        return expansion_base + (term * ambient + coordinate) * targets + target

    def quotient_xor(term: int, target: int) -> int:
        return quotient_xor_base + term * targets + target

    def u(coordinate: int, basis: int) -> int:
        return u_base + coordinate * cap + basis

    def lam(term: int, basis: int) -> int:
        return lam_base + term * cap + basis

    def ul_product(term: int, coordinate: int, basis: int) -> int:
        return ul_product_base + (term * quotient_coordinates + coordinate) * cap + basis

    def pivot(basis: int, position: int) -> int:
        return pivot_base + basis * terms + position

    def bc_product(term: int, b_coordinate: int, c_coordinate: int) -> int:
        return bc_product_base + (term * bdim + b_coordinate) * targets + c_coordinate

    def dual_xor(term: int, x_coordinate: int) -> int:
        return dual_xor_base + term * adim + x_coordinate

    def dual_u(coordinate: int, basis: int) -> int:
        return dual_u_base + coordinate * dual_cap + basis

    def dual_lam(term: int, basis: int) -> int:
        return dual_lam_base + term * dual_cap + basis

    def dual_ul_product(term: int, coordinate: int, basis: int) -> int:
        return (
            dual_ul_product_base
            + (term * dual_coordinates + coordinate) * dual_cap
            + basis
        )

    def dual_pivot(basis: int, position: int) -> int:
        return dual_pivot_base + basis * terms + position

    if minimal_terms:
        nonzero_c = True

    for term in range(terms):
        xnf.clause(*(avar(term, coordinate) for coordinate in range(adim)))
        xnf.clause(*(bvar(term, coordinate) for coordinate in range(bdim)))
        if nonzero_c:
            # This changes rank-at-most-r into an exact-rank-r encoding.  It
            # is sound for a closure campaign only when a separately checked
            # lower bound of r is already available: a zero C factor would
            # otherwise be a removable summand and give rank at most r-1.
            xnf.clause(*(coefficient(term, target) for target in range(targets)))

    if span_dependency_weight:
        # Matrix multiplication is concise in all three factors.  Therefore
        # the displayed A, B, and C factor columns must span their complete
        # coordinate spaces in every exact decomposition.  Equivalently, no
        # nonzero combination of coordinate rows can vanish across all terms.
        # Enumerating only low-Hamming-weight combinations is a redundant,
        # witness-free strengthening: it cannot remove an exact scheme and it
        # avoids the large affine symmetry of an explicit right inverse.
        def forbid_dependencies(
            dimension: int,
            variable: Callable[[int, int], int],
        ) -> None:
            for weight in range(1, min(span_dependency_weight, dimension) + 1):
                for coordinates in combinations(range(dimension), weight):
                    if weight == 1:
                        xnf.clause(
                            *(variable(term, coordinates[0]) for term in range(terms))
                        )
                        continue
                    parities = []
                    for term in range(terms):
                        parity = xnf.block(1)
                        xnf.xor(
                            [
                                *(variable(term, coordinate) for coordinate in coordinates),
                                parity,
                            ],
                            0,
                        )
                        parities.append(parity)
                    xnf.clause(*parities)

        forbid_dependencies(adim, avar)
        forbid_dependencies(bdim, bvar)
        forbid_dependencies(targets, coefficient)

    if minimal_terms:
        # In a minimum r-term decomposition, two summands cannot share any two
        # factors: combining the third factors replaces the pair by at most one
        # term.  Like nonzero_c, this mode relies on a separately checked lower
        # bound r before it can be used to close rank r+1.
        for left_term in range(terms):
            left_a = [avar(left_term, coordinate) for coordinate in range(adim)]
            left_b = [bvar(left_term, coordinate) for coordinate in range(bdim)]
            left_c = [
                coefficient(left_term, target) for target in range(targets)
            ]
            for right_term in range(left_term + 1, terms):
                right_a = [
                    avar(right_term, coordinate) for coordinate in range(adim)
                ]
                right_b = [
                    bvar(right_term, coordinate) for coordinate in range(bdim)
                ]
                right_c = [
                    coefficient(right_term, target) for target in range(targets)
                ]
                xnf.not_equal(left_a + left_b, right_a + right_b)
                xnf.not_equal(left_a + left_c, right_a + right_c)
                xnf.not_equal(left_b + left_c, right_b + right_c)

    if lex_terms:
        # Term zero is fixed to a coarse/stabilizer-orbit representative and
        # cannot in general occupy the first position of a global ordering.
        # Every other term remains freely permutable, including unused terms
        # with a zero C factor, so sorting terms 1..r-1 is equisatisfiable.
        def term_bits(term: int) -> list[int]:
            return [
                *(avar(term, coordinate) for coordinate in range(adim)),
                *(bvar(term, coordinate) for coordinate in range(bdim)),
                *(coefficient(term, target) for target in range(targets)),
            ]

        for term in range(1, terms - 1):
            xnf.lex_leq(term_bits(term), term_bits(term + 1))

    fixed_a = representative(a, 2, a_rank)
    fixed_b = representative(2, c, b_rank)
    if a_rank == b_rank == 1 and pairing == 0:
        fixed_b = 1 << c
    for coordinate in range(adim):
        variable = avar(0, coordinate)
        xnf.clause(variable if (fixed_a >> coordinate) & 1 else -variable)
    for coordinate in range(bdim):
        variable = bvar(0, coordinate)
        xnf.clause(variable if (fixed_b >> coordinate) & 1 else -variable)
    if fixed_c is not None:
        # fixed_c is row-major c x a, while target slices are indexed (i,k).
        for target in range(targets):
            i, k = divmod(target, c)
            variable = coefficient(0, target)
            value = (fixed_c >> (k * a + i)) & 1
            xnf.clause(variable if value else -variable)

    for term in range(terms):
        for ai in range(adim):
            for bi in range(bdim):
                xnf.and_gate(product(term, ai, bi), avar(term, ai), bvar(term, bi))

    for term in range(terms):
        for coordinate in range(ambient):
            ai, bi = divmod(coordinate, bdim)
            for target in range(targets):
                xnf.and_gate(
                    expansion(term, coordinate, target),
                    product(term, ai, bi),
                    coefficient(term, target),
                )

    for coordinate in range(ambient):
        ai, bi = divmod(coordinate, bdim)
        source_i, source_j = divmod(ai, 2)
        source_jb, source_k = divmod(bi, c)
        for target in range(targets):
            target_i, target_k = divmod(target, c)
            rhs = int(
                source_i == target_i
                and source_k == target_k
                and source_j == source_jb
            )
            xnf.xor(
                [expansion(term, coordinate, target) for term in range(terms)], rhs
            )

    if nonvacuous_quotient:
        # Projection modulo Q tensor <I_2> has coordinates
        # (r00+r11, r01, r10).  Its term-column matrix must have rank at
        # most terms-a*c, so factor it exactly as U*L.
        for term in range(terms):
            for i in range(a):
                for k in range(c):
                    target = i * c + k
                    xnf.xor(
                        [
                            product(term, 2 * i, k),
                            product(term, 2 * i + 1, c + k),
                            quotient_xor(term, target),
                        ],
                        0,
                    )

        def projected(term: int, coordinate: int) -> int:
            target, component = divmod(coordinate, 3)
            i, k = divmod(target, c)
            if component == 0:
                return quotient_xor(term, target)
            if component == 1:
                return product(term, 2 * i, c + k)
            return product(term, 2 * i + 1, k)

        if rref:
            # L has full row rank in its unique RREF gauge.  Extra zero U
            # columns allow projected rank strictly below cap.
            for basis in range(cap):
                xnf.clause(*(pivot(basis, position) for position in range(terms)))
                for first in range(terms):
                    for second in range(first + 1, terms):
                        xnf.clause(-pivot(basis, first), -pivot(basis, second))
            for basis in range(cap - 1):
                for position in range(terms):
                    for next_position in range(position + 1):
                        xnf.clause(
                            -pivot(basis, position),
                            -pivot(basis + 1, next_position),
                        )
            for basis in range(cap):
                for position in range(terms):
                    p = pivot(basis, position)
                    xnf.clause(-p, lam(position, basis))
                    for other_basis in range(cap):
                        if other_basis != basis:
                            xnf.clause(-p, -lam(position, other_basis))
                    for earlier in range(position):
                        xnf.clause(-p, -lam(earlier, basis))

        for term in range(terms):
            for coordinate in range(quotient_coordinates):
                for basis in range(cap):
                    xnf.and_gate(
                        ul_product(term, coordinate, basis),
                        u(coordinate, basis),
                        lam(term, basis),
                    )
                xnf.xor(
                    [
                        *(ul_product(term, coordinate, basis) for basis in range(cap)),
                        projected(term, coordinate),
                    ],
                    0,
                )

    if nonvacuous_dual:
        # Cyclically regroup Y tensor Z.  For each X coordinate (i,j), the
        # target slice is I_2 in the k index.  Project B_t tensor C_t modulo
        # that identity: (r00+r11, r01, r10).  Exactness then forces the
        # projected term-column rank to be at most terms-dim(X)=terms-2a.
        for term in range(terms):
            for b_coordinate in range(bdim):
                for c_coordinate in range(targets):
                    xnf.and_gate(
                        bc_product(term, b_coordinate, c_coordinate),
                        bvar(term, b_coordinate),
                        coefficient(term, c_coordinate),
                    )

        for term in range(terms):
            for i in range(a):
                for j in range(2):
                    x_coordinate = 2 * i + j
                    xnf.xor(
                        [
                            bc_product(term, 2 * j, 2 * i),
                            bc_product(term, 2 * j + 1, 2 * i + 1),
                            dual_xor(term, x_coordinate),
                        ],
                        0,
                    )

        def dual_projected(term: int, coordinate: int) -> int:
            x_coordinate, component = divmod(coordinate, 3)
            i, j = divmod(x_coordinate, 2)
            if component == 0:
                return dual_xor(term, x_coordinate)
            if component == 1:
                return bc_product(term, 2 * j, 2 * i + 1)
            return bc_product(term, 2 * j + 1, 2 * i)

        if rref:
            for basis in range(dual_cap):
                xnf.clause(
                    *(dual_pivot(basis, position) for position in range(terms))
                )
                for first in range(terms):
                    for second in range(first + 1, terms):
                        xnf.clause(
                            -dual_pivot(basis, first),
                            -dual_pivot(basis, second),
                        )
            for basis in range(dual_cap - 1):
                for position in range(terms):
                    for next_position in range(position + 1):
                        xnf.clause(
                            -dual_pivot(basis, position),
                            -dual_pivot(basis + 1, next_position),
                        )
            for basis in range(dual_cap):
                for position in range(terms):
                    p = dual_pivot(basis, position)
                    xnf.clause(-p, dual_lam(position, basis))
                    for other_basis in range(dual_cap):
                        if other_basis != basis:
                            xnf.clause(-p, -dual_lam(position, other_basis))
                    for earlier in range(position):
                        xnf.clause(-p, -dual_lam(earlier, basis))

        for term in range(terms):
            for coordinate in range(dual_coordinates):
                for basis in range(dual_cap):
                    xnf.and_gate(
                        dual_ul_product(term, coordinate, basis),
                        dual_u(coordinate, basis),
                        dual_lam(term, basis),
                    )
                xnf.xor(
                    [
                        *(
                            dual_ul_product(term, coordinate, basis)
                            for basis in range(dual_cap)
                        ),
                        dual_projected(term, coordinate),
                    ],
                    0,
                )

    comments = [
        f"exact GF(2) <{a},2,{c}> rank <= {terms}",
        (
            f"fixed term 0 A_rank={a_rank} A={fixed_a} B_rank={b_rank} "
            f"B={fixed_b} pairing={pairing if pairing is not None else 'na'}"
        ),
        f"fixed nonzero C={fixed_c}" if fixed_c is not None else "C not fixed",
        "AND Tseitin CNF plus native XOR tensor equations",
        (
            f"quotient rank <= {cap} in dimension {quotient_coordinates}; "
            f"nonvacuous={int(nonvacuous_quotient)} rref={int(rref)}"
            if quotient_rank else "quotient rank strengthening disabled"
        ),
        f"remaining-term lex symmetry break={int(lex_terms)}",
        f"every C factor nonzero={int(nonzero_c)}",
        f"minimum-rank pair distinctness={int(minimal_terms)}",
        (
            f"cyclic B*C quotient rank <= {dual_cap} in dimension "
            f"{dual_coordinates}; nonvacuous={int(nonvacuous_dual)} "
            f"rref={int(rref)}"
            if dual_inner2_quotient else "cyclic B*C quotient strengthening disabled"
        ),
        "five rank/pairing shards cover all nonzero fixed-term pair orbits",
    ]
    if span_dependency_weight:
        comments.insert(
            -2,
            "factor-span dependency exclusion through weight "
            f"{span_dependency_weight}",
        )
    xnf.write(output, comments)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    return {
        "a": a,
        "c": c,
        "terms": terms,
        "a_rank": a_rank,
        "b_rank": b_rank,
        "pairing": pairing if pairing is not None else "na",
        "fixed_c": fixed_c if fixed_c is not None else "na",
        "quotient_cap": cap,
        "quotient_coordinates": quotient_coordinates,
        "quotient_nonvacuous": nonvacuous_quotient,
        "rref": rref,
        "lex_terms": lex_terms,
        "nonzero_c": nonzero_c,
        "minimal_terms": minimal_terms,
        "dual_inner2_quotient": dual_inner2_quotient,
        "dual_quotient_cap": dual_cap,
        "dual_quotient_coordinates": dual_coordinates,
        "dual_quotient_nonvacuous": nonvacuous_dual,
        "span_dependency_weight": span_dependency_weight,
        "variables": xnf.variables,
        "clauses": len(xnf.clauses),
        "xors": len(xnf.xors),
        "constraints": len(xnf.clauses) + len(xnf.xors),
        "bytes": output.stat().st_size,
        "sha256": digest,
        "output": str(output),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--a", type=int, required=True)
    parser.add_argument("--c", type=int, required=True)
    parser.add_argument("--terms", type=int, required=True)
    parser.add_argument("--a-rank", type=int, choices=(1, 2), required=True)
    parser.add_argument("--b-rank", type=int, choices=(1, 2), required=True)
    parser.add_argument("--pairing", type=int, choices=(0, 1))
    parser.add_argument("--fixed-c", type=int)
    parser.add_argument("--quotient-rank", action="store_true")
    parser.add_argument("--no-rref", action="store_true")
    parser.add_argument("--lex-terms", action="store_true")
    parser.add_argument(
        "--nonzero-c",
        action="store_true",
        help="exact-rank mode; requires an independently checked rank >= terms",
    )
    parser.add_argument(
        "--minimal-terms",
        action="store_true",
        help="exact-minimum-rank mode; implies --nonzero-c and needs rank >= terms",
    )
    parser.add_argument(
        "--dual-inner2-quotient",
        action="store_true",
        help="also constrain cyclic B*C quotient rank; requires c=2",
    )
    parser.add_argument(
        "--span-dependency-weight",
        type=int,
        default=0,
        help=(
            "exclude factor-row dependencies through this Hamming weight; "
            "zero disables the redundant concise-tensor strengthening"
        ),
    )
    args = parser.parse_args()
    print(
        json.dumps(
            build(
                args.output,
                args.a,
                args.c,
                args.terms,
                args.a_rank,
                args.b_rank,
                args.pairing,
                args.fixed_c,
                args.quotient_rank,
                not args.no_rref,
                args.lex_terms,
                args.nonzero_c,
                args.minimal_terms,
                args.dual_inner2_quotient,
                args.span_dependency_weight,
            ),
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
