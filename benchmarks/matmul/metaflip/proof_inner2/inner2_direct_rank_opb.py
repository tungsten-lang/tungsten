#!/usr/bin/env python3
"""Exact proof-producing OPB encoding for GF(2) ``<a,2,c>`` tensor rank.

The formula asks whether the matrix-multiplication tensor has rank at most
``terms``.  It uses binary A and B factors and coefficients expressing every
one of the ``a*c`` target slices in the span of the resulting A tensor B
columns.  Thus it is an exact encoding, not a relaxation.

It also appends a redundant but useful quotient-rank condition.  After
reordering

    (F2^a tensor F2^2) tensor (F2^2 tensor F2^c)
      = Q tensor R,  dim Q = a*c, dim R = 4,

the target slices span ``K = Q tensor <I_2>``.  If ``S`` is spanned by at most
``terms`` product columns and contains K, then projection modulo K obeys

    rank(pi(S)) <= terms - a*c.

The projected matrix is factored exactly as V=UL.  By default L is put in
RREF, which removes its GL gauge without changing satisfiability.

Five shards are exhaustive.  Matrix ranks classify every pair except the
rank-one/rank-one case, where the contraction of the two shared-index vectors
is an additional invariant in F2.  Those two cases use ``--pairing 0|1``.
Choose any used term, permute it to term zero, and use the
GL(a) x GL(2) x GL(c) isotropy to put it in the corresponding normal form.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import tempfile
from pathlib import Path
from typing import Iterable


class Variables:
    def __init__(self) -> None:
        self.next = 1

    def block(self, size: int) -> int:
        assert size >= 0
        base = self.next
        self.next += size
        return base

    @property
    def count(self) -> int:
        return self.next - 1


class Emitter:
    def __init__(self, output: Path) -> None:
        output.parent.mkdir(parents=True, exist_ok=True)
        handle = tempfile.NamedTemporaryFile(
            mode="w", prefix=output.name + ".", suffix=".body", dir=output.parent,
            delete=False,
        )
        self.body_path = Path(handle.name)
        self.body = handle
        self.constraints = 0

    def line(self, coefficients: Iterable[tuple[int, int]], rhs: int) -> None:
        fields = [f"{coefficient:+d} x{variable}" for coefficient, variable in coefficients]
        assert fields
        self.body.write(" ".join(fields) + f" >= {rhs} ;\n")
        self.constraints += 1

    def equality(self, coefficients: list[tuple[int, int]], rhs: int) -> None:
        self.line(coefficients, rhs)
        self.line([(-coefficient, variable) for coefficient, variable in coefficients], -rhs)

    def and_gate(self, out: int, left: int, right: int) -> None:
        self.line([(1, left), (-1, out)], 0)
        self.line([(1, right), (-1, out)], 0)
        self.line([(-1, left), (-1, right), (1, out)], -1)

    def finish(self, output: Path, variables: int, comments: list[str]) -> None:
        self.body.close()
        temporary = output.with_name(output.name + ".tmp")
        with temporary.open("w") as target, self.body_path.open() as source:
            target.write(
                f"* #variable= {variables} #constraint= {self.constraints} "
                "#equal= 0 intsize= 64\n"
            )
            for comment in comments:
                target.write(f"* {comment}\n")
            shutil.copyfileobj(source, target)
        os.replace(temporary, output)
        self.body_path.unlink()


def representative(rows: int, columns: int, rank: int) -> int:
    assert rank in (1, 2)
    assert rows >= rank and columns >= rank
    return sum(1 << (i * columns + i) for i in range(rank))


def build(
    output: Path,
    a: int,
    c: int,
    terms: int,
    a_rank: int,
    b_rank: int,
    pairing: int | None,
    quotient_rank: bool,
    rref: bool,
    fixed_c: int | None = None,
) -> dict[str, int | str | bool]:
    assert a >= 2 and c >= 2 and terms >= 1
    assert a_rank in (1, 2) and b_rank in (1, 2)
    if a_rank == b_rank == 1:
        assert pairing in (0, 1)
    else:
        assert pairing is None
    adim, bdim, targets = 2 * a, 2 * c, a * c
    ambient = adim * bdim
    if fixed_c is not None:
        assert 0 < fixed_c < (1 << targets)
    quotient_coordinates = 3 * targets
    cap = terms - targets
    if quotient_rank:
        assert cap >= 0, "rank is already below the C flattening bound a*c"

    variables = Variables()
    a_base = variables.block(terms * adim)
    b_base = variables.block(terms * bdim)
    product_base = variables.block(terms * ambient)
    coefficient_base = variables.block(terms * targets)
    expansion_base = variables.block(terms * ambient * targets)
    target_parity_bits = (terms // 2).bit_length()
    target_parity_base = variables.block(ambient * targets * target_parity_bits)

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

    def target_parity(coordinate: int, target: int, bit: int) -> int:
        return target_parity_base + (coordinate * targets + target) * target_parity_bits + bit

    # Quotient-rank variables are allocated only when the condition is
    # non-vacuous.  The two off-diagonal quotient coordinates alias A*B product
    # variables; only r00+r11 needs an explicit XOR output.
    nonvacuous_quotient = quotient_rank and cap < min(quotient_coordinates, terms)
    xor_base = variables.block(terms * targets) if nonvacuous_quotient else 0
    xor_carry_base = variables.block(terms * targets) if nonvacuous_quotient else 0
    u_base = variables.block(quotient_coordinates * cap) if nonvacuous_quotient else 0
    lam_base = variables.block(terms * cap) if nonvacuous_quotient else 0
    ul_product_base = (
        variables.block(terms * quotient_coordinates * cap)
        if nonvacuous_quotient else 0
    )
    quotient_parity_bits = (cap // 2).bit_length() if nonvacuous_quotient else 0
    quotient_parity_base = (
        variables.block(terms * quotient_coordinates * quotient_parity_bits)
        if nonvacuous_quotient else 0
    )
    pivot_base = variables.block(cap * terms) if nonvacuous_quotient and rref else 0

    def xor_value(term: int, target: int) -> int:
        return xor_base + term * targets + target

    def xor_carry(term: int, target: int) -> int:
        return xor_carry_base + term * targets + target

    def u(coordinate: int, basis: int) -> int:
        return u_base + coordinate * cap + basis

    def lam(term: int, basis: int) -> int:
        return lam_base + term * cap + basis

    def ul_product(term: int, coordinate: int, basis: int) -> int:
        return ul_product_base + (term * quotient_coordinates + coordinate) * cap + basis

    def quotient_parity(term: int, coordinate: int, bit: int) -> int:
        return quotient_parity_base + (
            term * quotient_coordinates + coordinate
        ) * quotient_parity_bits + bit

    def pivot(basis: int, position: int) -> int:
        return pivot_base + basis * terms + position

    emitter = Emitter(output)

    # Every displayed term has nonzero adjacent factors.  Terms with all-zero
    # C coefficients are harmless padding, so the formula means rank <= terms.
    for term in range(terms):
        emitter.line([(1, avar(term, coordinate)) for coordinate in range(adim)], 1)
        emitter.line([(1, bvar(term, coordinate)) for coordinate in range(bdim)], 1)

    fixed_a = representative(a, 2, a_rank)
    fixed_b = representative(2, c, b_rank)
    if a_rank == b_rank == 1 and pairing == 0:
        # A=x*e0^T and B=e1*z^T, so the invariant contraction is zero.
        fixed_b = 1 << c
    for coordinate in range(adim):
        value = (fixed_a >> coordinate) & 1
        emitter.line([(1 if value else -1, avar(0, coordinate))], value if value else 0)
    for coordinate in range(bdim):
        value = (fixed_b >> coordinate) & 1
        emitter.line([(1 if value else -1, bvar(0, coordinate))], value if value else 0)
    if fixed_c is not None:
        # fixed_c is row-major c x a, while target slices are indexed (i,k).
        for target in range(targets):
            i, k = divmod(target, c)
            value = (fixed_c >> (k * a + i)) & 1
            emitter.line(
                [(1 if value else -1, coefficient(0, target))],
                value if value else 0,
            )

    # D_t = A_t tensor B_t.
    for term in range(terms):
        for ai in range(adim):
            for bi in range(bdim):
                emitter.and_gate(product(term, ai, bi), avar(term, ai), bvar(term, bi))

    # E_{t,s,q} = D_t[s] * C_t[q].
    for term in range(terms):
        for coordinate in range(ambient):
            ai, bi = divmod(coordinate, bdim)
            for target in range(targets):
                emitter.and_gate(
                    expansion(term, coordinate, target),
                    product(term, ai, bi),
                    coefficient(term, target),
                )

    # Exact tensor equations: target slice (i,k) is I_2 in the shared index.
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
            expression = [
                (1, expansion(term, coordinate, target)) for term in range(terms)
            ]
            expression.extend(
                (-(2 << bit), target_parity(coordinate, target, bit))
                for bit in range(target_parity_bits)
            )
            emitter.equality(expression, rhs)

    if nonvacuous_quotient:
        # pi(y tensor p) = (r00+r11, r01, r10).
        for term in range(terms):
            for i in range(a):
                for k in range(c):
                    target = i * c + k
                    left = product(term, 2 * i, k)
                    right = product(term, 2 * i + 1, c + k)
                    emitter.equality(
                        [
                            (1, left),
                            (1, right),
                            (-1, xor_value(term, target)),
                            (-2, xor_carry(term, target)),
                        ],
                        0,
                    )

        def projected(term: int, coordinate: int) -> int:
            target, component = divmod(coordinate, 3)
            i, k = divmod(target, c)
            if component == 0:
                return xor_value(term, target)
            if component == 1:
                return product(term, 2 * i, c + k)
            return product(term, 2 * i + 1, k)

        if rref:
            # L has full row rank and is its unique RREF representative.
            for basis in range(cap):
                choices = [(1, pivot(basis, position)) for position in range(terms)]
                emitter.line(choices, 1)
                emitter.line([(-1, variable) for _, variable in choices], -1)
            for basis in range(cap - 1):
                for position in range(terms):
                    for next_position in range(position + 1):
                        emitter.line(
                            [
                                (-1, pivot(basis, position)),
                                (-1, pivot(basis + 1, next_position)),
                            ],
                            -1,
                        )
            for basis in range(cap):
                for position in range(terms):
                    p = pivot(basis, position)
                    emitter.line([(-1, p), (1, lam(position, basis))], 0)
                    for other_basis in range(cap):
                        if other_basis != basis:
                            emitter.line(
                                [(-1, p), (-1, lam(position, other_basis))], -1
                            )
                    for earlier in range(position):
                        emitter.line([(-1, p), (-1, lam(earlier, basis))], -1)

        for term in range(terms):
            for coordinate in range(quotient_coordinates):
                for basis in range(cap):
                    emitter.and_gate(
                        ul_product(term, coordinate, basis),
                        u(coordinate, basis),
                        lam(term, basis),
                    )
                expression = [
                    (1, ul_product(term, coordinate, basis)) for basis in range(cap)
                ]
                expression.append((-1, projected(term, coordinate)))
                expression.extend(
                    (-(2 << bit), quotient_parity(term, coordinate, bit))
                    for bit in range(quotient_parity_bits)
                )
                emitter.equality(expression, 0)

    comments = [
        f"exact GF(2) <{a},2,{c}> rank <= {terms}",
        (
            f"fixed term 0 A_rank={a_rank} A={fixed_a} B_rank={b_rank} "
            f"B={fixed_b} pairing={pairing if pairing is not None else 'na'}"
        ),
        f"fixed nonzero C={fixed_c}" if fixed_c is not None else "C not fixed",
        f"target_slices={targets} ambient_AB={ambient}",
        (
            f"quotient rank <= {cap} in dimension {quotient_coordinates}; "
            f"nonvacuous={int(nonvacuous_quotient)} rref={int(rref)}"
            if quotient_rank else "quotient rank strengthening disabled"
        ),
        "five rank/pairing shards cover all nonzero fixed-term pair orbits",
    ]
    emitter.finish(output, variables.count, comments)
    return {
        "a": a,
        "c": c,
        "terms": terms,
        "a_rank": a_rank,
        "b_rank": b_rank,
        "pairing": pairing if pairing is not None else "na",
        "fixed_c": fixed_c if fixed_c is not None else "na",
        "variables": variables.count,
        "constraints": emitter.constraints,
        "quotient_cap": cap,
        "quotient_coordinates": quotient_coordinates,
        "quotient_nonvacuous": nonvacuous_quotient,
        "rref": rref,
        "bytes": output.stat().st_size,
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
    parser.add_argument("--without-quotient-rank", action="store_true")
    parser.add_argument("--no-rref", action="store_true")
    parser.add_argument("--fixed-c", type=int)
    args = parser.parse_args()
    stats = build(
        args.output,
        args.a,
        args.c,
        args.terms,
        args.a_rank,
        args.b_rank,
        args.pairing,
        not args.without_quotient_rank,
        not args.no_rref,
        args.fixed_c,
    )
    print(json.dumps(stats, sort_keys=True))


if __name__ == "__main__":
    main()
