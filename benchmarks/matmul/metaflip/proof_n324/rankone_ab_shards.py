#!/usr/bin/env python3
"""Generate the rank-19 residual with distinct rank-one A and rank-one B.

The A support follows from the checked n324 orbit-29 lemma.  The B rank
restriction follows independently from the checked, factor-permuted n243
rank-two lemma.  B factors are deliberately allowed to repeat.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

from fixed_a_shards import (
    Xnf,
    left_b,
    left_c,
    right_b,
    right_c,
    write_formula,
)
from n324_common import (
    RANK_ONE_A,
    apply_a,
    gl_packed,
    inverse_square,
    rank32,
    rank_rows,
    row_times,
)


def rank24(value: int) -> int:
    return rank_rows([value & 15, value >> 4], 4)


RANK_ONE_B = tuple(value for value in range(1, 256) if rank24(value) == 1)
assert len(RANK_ONE_B) == 45


def mul_square(a: int, b: int, n: int) -> int:
    mask = (1 << n) - 1
    return sum(
        row_times((a >> (n * row)) & mask, b, n) << (n * row)
        for row in range(n)
    )


def identity(n: int) -> int:
    return sum(1 << (n * row + row) for row in range(n))


def compose(
    first: tuple[int, int, int], second: tuple[int, int, int]
) -> tuple[int, int, int]:
    """Compose tensor symmetries in application order."""
    left1, right1, shared1 = first
    left2, right2, shared2 = second
    return (
        mul_square(left2, left1, 3),
        mul_square(right1, right2, 2),
        mul_square(shared1, shared2, 4),
    )


def closure(
    generators: list[tuple[int, int, int]],
) -> set[tuple[int, int, int]]:
    unit = (identity(3), identity(2), identity(4))
    seen = {unit}
    stack = [unit]
    while stack:
        current = stack.pop()
        for generator in generators:
            image = compose(current, generator)
            if image not in seen:
                seen.add(image)
                stack.append(image)
    return seen


def residual_group(
    missing: tuple[int, int],
    canonical_a: int,
    fixed_b: int,
    fixed_c: int,
) -> list[tuple[int, int, int]]:
    """Exact stabilizer of the A support and fixed canonical tensor term."""
    group = []
    for left in gl_packed(3):
        left_inverse = inverse_square(left, 3)
        for right in gl_packed(2):
            right_inverse = inverse_square(right, 2)
            if {apply_a(value, left, right) for value in missing} != set(missing):
                continue
            if apply_a(canonical_a, left, right) != canonical_a:
                continue
            transformed_b = left_b(right_inverse, fixed_b)
            transformed_c_right = right_c(fixed_c, left_inverse)
            for shared in gl_packed(4):
                if right_b(transformed_b, shared) != fixed_b:
                    continue
                shared_inverse = inverse_square(shared, 4)
                if left_c(shared_inverse, transformed_c_right) != fixed_c:
                    continue
                group.append((left, right, shared))
    assert len(group) == len(set(group))
    return sorted(group)


def group_generators(
    group: list[tuple[int, int, int]],
) -> list[tuple[int, int, int]]:
    generators = []
    generated = closure(generators)
    for element in group:
        if element in generated:
            continue
        generators.append(element)
        generated = closure(generators)
    assert generated == set(group)
    return generators


def linear_image_masks(width: int, transform) -> list[int]:
    masks = [0] * width
    for source in range(width):
        image = transform(1 << source)
        for output in range(width):
            if (image >> output) & 1:
                masks[output] |= 1 << source
    return masks


def add_lex_leader(
    xnf: Xnf, variables: list[int], transformed: list[list[int]]
) -> None:
    """Constrain variables <=lex a linearly transformed symmetry image."""
    assert len(variables) == len(transformed)
    prefix = xnf.var()
    xnf.add(prefix)
    for position, (variable, expression) in enumerate(zip(variables, transformed)):
        assert expression
        if expression == [variable]:
            continue
        image = xnf.var()
        xnf.xor_eq([image, *expression], 0)
        xnf.add(-prefix, -variable, image)
        if position + 1 != len(variables):
            different = xnf.var()
            xnf.xor_eq([different, variable, image], 0)
            next_prefix = xnf.var()
            xnf.add(-next_prefix, prefix)
            xnf.add(-next_prefix, -different)
            xnf.add(next_prefix, -prefix, different)
            prefix = next_prefix


def add_residual_lex_leaders(
    xnf: Xnf,
    a: list[int],
    b: list[list[int]],
    c: list[list[int]],
    fixed_term: int,
    symmetries: list[tuple[int, int, int]],
) -> None:
    by_a = {value: index for index, value in enumerate(a)}
    ordered_terms = [term for term in range(19) if term != fixed_term]
    primary = [b[term][bit] for term in ordered_terms for bit in range(8)]
    primary.extend(c[term][bit] for term in ordered_terms for bit in range(12))
    for left, right, shared in symmetries:
        left_inverse = inverse_square(left, 3)
        right_inverse = inverse_square(right, 2)
        shared_inverse = inverse_square(shared, 4)
        b_masks = linear_image_masks(
            8,
            lambda value: right_b(left_b(right_inverse, value), shared),
        )
        c_masks = linear_image_masks(
            12,
            lambda value: right_c(left_c(shared_inverse, value), left_inverse),
        )
        source_for_destination = {}
        for source, avalue in enumerate(a):
            destination = by_a[apply_a(avalue, left, right)]
            source_for_destination[destination] = source
        transformed = []
        for destination in ordered_terms:
            source = source_for_destination[destination]
            transformed.extend(
                [
                    [
                        b[source][bit]
                        for bit in range(8)
                        if (mask >> bit) & 1
                    ]
                    for mask in b_masks
                ]
            )
        for destination in ordered_terms:
            source = source_for_destination[destination]
            transformed.extend(
                [
                    [
                        c[source][bit]
                        for bit in range(12)
                        if (mask >> bit) & 1
                    ]
                    for mask in c_masks
                ]
            )
        add_lex_leader(xnf, primary, transformed)


def factor_rank_one_b(value: int) -> tuple[int, int]:
    """Return the unique nonzero p in F2^2, q in F2^4 with B=p*q^T."""
    row0, row1 = value & 15, value >> 4
    assert rank24(value) == 1
    if row0 == 0:
        return 2, row1
    if row1 == 0:
        return 1, row0
    assert row0 == row1
    return 3, row0


def enumerate_rank_one_b_cases() -> tuple[
    dict[tuple[tuple[int, int], int], dict[int, tuple[int, ...]]],
    dict[str, int],
]:
    """Re-derive the complete pair-orbit cover after restricting B to rank 1."""
    gl4 = [(shared, inverse_square(shared, 4)) for shared in gl_packed(4)]

    # Normalize all 45 rank-one B forms.  The three row-vector types are the
    # possible nonzero p in the factorization B=p*q^T.
    to_normal: dict[int, tuple[int, int]] = {}
    for b in RANK_ONE_B:
        row0, row1 = b & 15, b >> 4
        target = 1 if row1 == 0 else 16 if row0 == 0 else 17
        assert row0 == 0 or row1 == 0 or row0 == row1
        matches = [
            inverse for shared, inverse in gl4 if right_b(b, shared) == target
        ]
        assert matches
        to_normal[b] = target, matches[0]

    # Once B is normalized, quotient C by the corresponding GL(4,2)
    # stabilizer.  C is always nonzero.
    ccanon: dict[int, list[int]] = {}
    for b in (1, 16, 17):
        stabilizer_inverses = [
            inverse for shared, inverse in gl4 if right_b(b, shared) == b
        ]
        canon = [0] * 4096
        for c in range(1, 4096):
            canon[c] = min(
                left_c(inverse, c) for inverse in stabilizer_inverses
            )
        ccanon[b] = canon

    def canonical_pair(b: int, c: int) -> tuple[int, int]:
        assert b in to_normal and 1 <= c < 4096
        target, inverse = to_normal[b]
        return target, ccanon[target][left_c(inverse, c)]

    nodes = sorted(
        {
            canonical_pair(b, c)
            for b in RANK_ONE_B
            for c in range(1, 4096)
        }
    )

    gl3, gl2 = gl_packed(3), gl_packed(2)
    result = {}
    expected_k_sizes = {(1, 2): 48, (1, 4): 16, (1, 8): 8}
    for missing, canonical_a in (((1, 2), 3), ((1, 4), 5), ((1, 8), 15)):
        kgroup = []
        for left in gl3:
            left_inverse = inverse_square(left, 3)
            for right in gl2:
                right_inverse = inverse_square(right, 2)
                if {apply_a(value, left, right) for value in missing} != set(
                    missing
                ):
                    continue
                if apply_a(canonical_a, left, right) != canonical_a:
                    continue
                kgroup.append((right_inverse, left_inverse))
        assert len(kgroup) == expected_k_sizes[missing]

        unseen = set(nodes)
        representatives = []
        covered = set()
        while unseen:
            seed = min(unseen)
            orbit: set[tuple[int, int]] = set()
            stack = [seed]
            while stack:
                pair = stack.pop()
                if pair in orbit:
                    continue
                orbit.add(pair)
                b, c = pair
                for right_inverse, left_inverse in kgroup:
                    image = canonical_pair(
                        left_b(right_inverse, b), right_c(c, left_inverse)
                    )
                    if image not in orbit:
                        stack.append(image)
            assert not covered.intersection(orbit)
            covered.update(orbit)
            unseen.difference_update(orbit)
            representatives.append(min(orbit))
        assert covered == set(nodes)
        by_b: dict[int, list[int]] = {}
        for b, c in representatives:
            by_b.setdefault(b, []).append(c)
        assert set(by_b) <= {1, 16, 17}
        result[(missing, canonical_a)] = {
            b: tuple(cs) for b, cs in sorted(by_b.items())
        }

    counts = {
        "rank_one_b_forms": len(RANK_ONE_B),
        "gl4_pair_nodes": len(nodes),
        "missing_1_2_shards": sum(map(len, result[((1, 2), 3)].values())),
        "missing_1_4_shards": sum(map(len, result[((1, 4), 5)].values())),
        "missing_1_8_shards": sum(map(len, result[((1, 8), 15)].values())),
    }
    return result, counts


def add_rank_one_b(
    xnf: Xnf, b: list[list[int]]
) -> tuple[list[list[int]], list[list[int]]]:
    """Encode every B_t as the outer product of nonzero 2- and 4-vectors."""
    p = [[xnf.var() for _ in range(2)] for _ in range(19)]
    q = [[xnf.var() for _ in range(4)] for _ in range(19)]
    for term in range(19):
        xnf.add(*p[term])
        xnf.add(*q[term])
        for row in range(2):
            for col in range(4):
                product = b[term][row * 4 + col]
                xnf.add(-product, p[term][row])
                xnf.add(-product, q[term][col])
                xnf.add(product, -p[term][row], -q[term][col])
        # Redundant but useful propagation; p,q nonzero already imply this.
        xnf.add(*b[term])
    return p, q


def add_choice_indicators(
    xnf: Xnf, p: list[list[int]], q: list[list[int]]
) -> list[list[int]]:
    """Expose the unique one-hot value of every outer-product B factor."""
    choices = []
    for term in range(19):
        term_choices = []
        for value in RANK_ONE_B:
            pvalue, qvalue = factor_rank_one_b(value)
            pattern = [
                variable if (pvalue >> bit) & 1 else -variable
                for bit, variable in enumerate(p[term])
            ]
            pattern.extend(
                variable if (qvalue >> bit) & 1 else -variable
                for bit, variable in enumerate(q[term])
            )
            choice = xnf.var()
            for literal in pattern:
                xnf.add(-choice, literal)
            xnf.add(choice, *[-literal for literal in pattern])
            term_choices.append(choice)
        # Redundant: nonzero p and q plus the equivalences already force one
        # of the 45 choices, but this clause improves early propagation.
        xnf.add(*term_choices)
        choices.append(term_choices)
    return choices


def add_at_most(xnf: Xnf, variables: list[int], capacity: int) -> None:
    """Sinz-style unary sequential counter for sum(variables) <= capacity."""
    assert capacity >= 0
    if capacity >= len(variables):
        return
    if capacity == 0:
        for variable in variables:
            xnf.add(-variable)
        return
    previous = None
    for variable in variables:
        current = [xnf.var() for _ in range(capacity)]
        xnf.add(-variable, current[0])
        if previous is not None:
            xnf.add(-variable, -previous[-1])
            for level in range(capacity):
                xnf.add(-previous[level], current[level])
            for level in range(1, capacity):
                xnf.add(-variable, -previous[level - 1], current[level])
        previous = current


def read_occurrence_bounds(
    path: Path,
    max_points: int,
    max_capacity: int,
    max_rows: int | None,
) -> list[tuple[int, tuple[int, ...]]]:
    rows = []
    for line in path.read_text().splitlines():
        values = tuple(map(int, line.split()))
        capacity, points = values[0], values[1:]
        assert points and set(points) <= set(RANK_ONE_B)
        if len(points) <= max_points and capacity <= max_capacity:
            rows.append((capacity, points))
    rows.sort(key=lambda row: (row[0], len(row[1]), row[1]))
    if max_rows is not None:
        rows = rows[:max_rows]
    assert len(rows) == len(set(rows))
    return rows


def add_occurrence_bounds(
    xnf: Xnf,
    choices: list[list[int]],
    rows: list[tuple[int, tuple[int, ...]]],
) -> None:
    index = {value: offset for offset, value in enumerate(RANK_ONE_B)}
    for capacity, points in rows:
        members = []
        for term in range(19):
            selected = [choices[term][index[value]] for value in points]
            if len(selected) == 1:
                members.append(selected[0])
                continue
            member = xnf.var()
            for choice in selected:
                xnf.add(-choice, member)
            xnf.add(-member, *selected)
            members.append(member)
        add_at_most(xnf, members, capacity)


def add_full_b_span(xnf: Xnf, a: list[int], b: list[list[int]]) -> None:
    """Add the necessary rank-eight B-span constraints for A contractions."""
    parity = {}
    for term in range(19):
        for functional in range(1, 256):
            value = xnf.var()
            parity[term, functional] = value
            xnf.xor_eq(
                [
                    value,
                    *[
                        b[term][bit]
                        for bit in range(8)
                        if (functional >> bit) & 1
                    ],
                ],
                0,
            )
    rank_two_functionals = [
        functional for functional in range(1, 64) if rank32(functional) == 2
    ]
    assert len(rank_two_functionals) == 42
    for functional_a in rank_two_functionals:
        active = [
            term
            for term, avalue in enumerate(a)
            if (functional_a & avalue).bit_count() & 1
        ]
        # The contraction has B-flattening rank 4*rank(functional_a)=8.
        assert 10 <= len(active) <= 12
        for functional_b in range(1, 256):
            xnf.add(*[parity[term, functional_b] for term in active])


def build_xnf(
    missing: tuple[int, int],
    canonical_a: int,
    fixed_b: int,
    allowed_c: tuple[int, ...],
    fixed_c: int | None,
    full_b_span: bool,
    occurrence_rows: list[tuple[int, tuple[int, ...]]],
    lex_symmetries: list[tuple[int, int, int]],
) -> bytes:
    a = [value for value in RANK_ONE_A if value not in missing]
    assert len(a) == 19 and len(set(a)) == 19 and canonical_a in a
    term = a.index(canonical_a)
    xnf = Xnf()
    b = [[xnf.var() for _ in range(8)] for _ in range(19)]
    c = [[xnf.var() for _ in range(12)] for _ in range(19)]
    for row in c:
        xnf.add(*row)
    p, q = add_rank_one_b(xnf, b)

    if occurrence_rows:
        choices = add_choice_indicators(xnf, p, q)
        add_occurrence_bounds(xnf, choices, occurrence_rows)

    fixed_p, fixed_q = factor_rank_one_b(fixed_b)
    for bit, variable in enumerate(p[term]):
        xnf.add(variable if (fixed_p >> bit) & 1 else -variable)
    for bit, variable in enumerate(q[term]):
        xnf.add(variable if (fixed_q >> bit) & 1 else -variable)

    if fixed_c is None:
        allowed = set(allowed_c)
        for mask in range(1 << 12):
            if mask in allowed:
                continue
            xnf.add(
                *[
                    -variable if (mask >> bit) & 1 else variable
                    for bit, variable in enumerate(c[term])
                ]
            )
    else:
        assert fixed_c in allowed_c
        for bit, variable in enumerate(c[term]):
            xnf.add(variable if (fixed_c >> bit) & 1 else -variable)

    if lex_symmetries:
        add_residual_lex_leaders(xnf, a, b, c, term, lex_symmetries)

    if full_b_span:
        add_full_b_span(xnf, a, b)

    d = [
        [[xnf.var() for _ in range(12)] for _ in range(8)] for _ in range(19)
    ]
    for t in range(19):
        for bj in range(8):
            for ck in range(12):
                product = d[t][bj][ck]
                xnf.add(-product, b[t][bj])
                xnf.add(-product, c[t][ck])
                xnf.add(product, -b[t][bj], -c[t][ck])
    for ai in range(6):
        i, j = divmod(ai, 2)
        for bj in range(8):
            jb, k = divmod(bj, 4)
            for ck in range(12):
                kc, ic = divmod(ck, 3)
                rhs = int(j == jb and k == kc and i == ic)
                xnf.xor_eq(
                    [d[t][bj][ck] for t in range(19) if (a[t] >> ai) & 1],
                    rhs,
                )
    return xnf.render(
        [
            "GF(2) <3,2,4> rank-19 residual after both checked mode lemmas",
            f"missing_rank1_A {missing[0]} {missing[1]}",
            f"A_factors_distinct {' '.join(map(str, a))}",
            "all_B_factors_rank_one B_repetitions_allowed",
            f"canonical_term {term} A {canonical_a} fixed_B {fixed_b}",
            f"allowed_C_count {len(allowed_c)}",
            f"fixed_C {fixed_c if fixed_c is not None else 'aggregate'}",
            f"full_B_span {int(full_b_span)}",
            f"B_subspace_occurrence_bounds {len(occurrence_rows)}",
            f"residual_lex_leaders {len(lex_symmetries)}",
            "outer-product B encoding, AND Tseitin clauses, 576 native XOR equations",
        ]
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir", type=Path)
    parser.add_argument(
        "--mode", choices=("aggregate", "split", "all"), default="all"
    )
    parser.add_argument("--full-b-span", action="store_true")
    parser.add_argument("--occurrence-table", type=Path)
    parser.add_argument("--occurrence-max-points", type=int, default=1)
    parser.add_argument("--occurrence-max-capacity", type=int, default=19)
    parser.add_argument("--occurrence-max-rows", type=int)
    parser.add_argument("--only-missing", nargs=2, type=int)
    parser.add_argument("--only-b", type=int)
    parser.add_argument("--only-c", type=int)
    parser.add_argument("--lex-generators", action="store_true")
    args = parser.parse_args()

    cases, counts = enumerate_rank_one_b_cases()
    occurrence_rows = []
    if args.occurrence_table:
        occurrence_rows = read_occurrence_bounds(
            args.occurrence_table,
            args.occurrence_max_points,
            args.occurrence_max_capacity,
            args.occurrence_max_rows,
        )
        print(f"selected_B_subspace_occurrence_bounds={len(occurrence_rows)}")
    if args.lex_generators and args.mode != "split":
        parser.error("--lex-generators requires --mode split")
    if args.only_c is not None and args.mode != "split":
        parser.error("--only-c requires --mode split")
    selected_missing = tuple(args.only_missing) if args.only_missing else None
    print(
        "rank_one_B_orbit_audit=PASS "
        + " ".join(f"{key}={value}" for key, value in counts.items())
    )
    args.output_dir.mkdir(parents=True, exist_ok=True)
    manifest: list[tuple[str, str]] = []
    for (missing, canonical_a), by_b in cases.items():
        if selected_missing is not None and missing != selected_missing:
            continue
        for fixed_b, allowed_c in by_b.items():
            if args.only_b is not None and fixed_b != args.only_b:
                continue
            assert rank24(fixed_b) == 1
            stem = (
                f"n324_rank19_rank1ab_missing_{missing[0]}_{missing[1]}"
                f"_a{canonical_a}_b{fixed_b}"
            )
            if args.mode in ("aggregate", "all"):
                write_formula(
                    args.output_dir / f"{stem}.xnf",
                    build_xnf(
                        missing,
                        canonical_a,
                        fixed_b,
                        allowed_c,
                        None,
                        args.full_b_span,
                        occurrence_rows,
                        [],
                    ),
                    manifest,
                )
            if args.mode in ("split", "all"):
                for fixed_c in allowed_c:
                    if args.only_c is not None and fixed_c != args.only_c:
                        continue
                    lex_symmetries = []
                    if args.lex_generators:
                        group = residual_group(
                            missing, canonical_a, fixed_b, fixed_c
                        )
                        lex_symmetries = group_generators(group)
                        unit = (identity(3), identity(2), identity(4))
                        lex_symmetries = [
                            symmetry
                            for symmetry in lex_symmetries
                            if symmetry != unit
                        ]
                        print(
                            f"lex_case={missing},{fixed_b},{fixed_c} "
                            f"group={len(group)} generators={len(lex_symmetries)}"
                        )
                    write_formula(
                        args.output_dir / f"{stem}_c{fixed_c}.xnf",
                        build_xnf(
                            missing,
                            canonical_a,
                            fixed_b,
                            allowed_c,
                            fixed_c,
                            args.full_b_span,
                            occurrence_rows,
                            lex_symmetries,
                        ),
                        manifest,
                    )
    manifest.sort(key=lambda item: item[1])
    manifest_text = "".join(
        f"{digest}  {name}\n" for digest, name in manifest
    )
    (args.output_dir / "manifest.sha256").write_text(manifest_text)
    print(
        f"formulas={len(manifest)} manifest_sha256="
        f"{hashlib.sha256(manifest_text.encode()).hexdigest()}"
    )


if __name__ == "__main__":
    main()
