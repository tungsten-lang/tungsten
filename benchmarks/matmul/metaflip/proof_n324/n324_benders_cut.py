#!/usr/bin/env python3
"""Extract and independently validate a Gaussian Benders cut for n324."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
from pathlib import Path

from n324_common import RANK_ONE_A, rank_rows


def parse_model(path: Path) -> set[int]:
    positive = set()
    assert "s SATISFIABLE" in path.read_text().splitlines()
    for line in path.read_text().splitlines():
        if not line.startswith("v "):
            continue
        for token in line.split()[1:]:
            if token.startswith("x"):
                positive.add(int(token[1:]))
            else:
                assert token.startswith("-x"), token
    return positive


def equations(a: tuple[int, ...], b: list[int]) -> list[tuple[int, int]]:
    """Return (228-bit C row, rhs) in canonical 6*8*12 order."""
    result = []
    for ai in range(6):
        i, j = divmod(ai, 2)
        for bj in range(8):
            jb, k = divmod(bj, 4)
            for ck in range(12):
                kc, ic = divmod(ck, 3)
                row = 0
                for term in range(19):
                    if ((a[term] >> ai) & 1) and ((b[term] >> bj) & 1):
                        row ^= 1 << (term * 12 + ck)
                result.append((row, int(j == jb and k == kc and i == ic)))
    assert len(result) == 576
    return result


def all_dependencies(rows: list[tuple[int, int]]) -> list[tuple[int, int]]:
    """Return Gaussian dependency selectors as (y, y*rhs)."""
    basis: dict[int, tuple[int, int, int]] = {}
    dependencies = []
    for equation_index, (variables, rhs) in enumerate(rows):
        provenance = 1 << equation_index
        while variables:
            pivot = variables.bit_length() - 1
            if pivot not in basis:
                basis[pivot] = variables, rhs, provenance
                break
            old_variables, old_rhs, old_provenance = basis[pivot]
            variables ^= old_variables
            rhs ^= old_rhs
            provenance ^= old_provenance
        else:
            dependencies.append((provenance, rhs))
    return dependencies


def contradiction_witnesses(rows: list[tuple[int, int]]) -> list[int]:
    """Return dependency selectors y with y*M=0 and y*rhs=1."""
    witnesses = [provenance for provenance, rhs in all_dependencies(rows) if rhs]
    assert witnesses, "the supplied B assignment has a consistent C system"
    return witnesses


def column_dot(witness: int, avalue: int, bvalue: int, cbit: int) -> int:
    value = 0
    for ai in range(6):
        if not ((avalue >> ai) & 1):
            continue
        for bj in range(8):
            if not ((bvalue >> bj) & 1):
                continue
            equation = (ai * 8 + bj) * 12 + cbit
            value ^= (witness >> equation) & 1
    return value


def column_masks(
    a: tuple[int, ...], rank_one_b: tuple[int, ...]
) -> list[list[list[int]]]:
    """Precompute [term][B][C-bit] 576-bit coefficient columns."""
    result = []
    for avalue in a:
        by_b = []
        for bvalue in rank_one_b:
            by_c = []
            for cbit in range(12):
                mask = 0
                for ai in range(6):
                    if not ((avalue >> ai) & 1):
                        continue
                    for bj in range(8):
                        if (bvalue >> bj) & 1:
                            mask |= 1 << ((ai * 8 + bj) * 12 + cbit)
                by_c.append(mask)
            by_b.append(by_c)
        result.append(by_b)
    return result


def lift_block_witness(block_witness: int, cbit: int) -> int:
    """Embed a 48-row A-by-B selector into one of the 12 C slices."""
    return sum(
        1 << (row * 12 + cbit)
        for row in range(48)
        if (block_witness >> row) & 1
    )


def block_system(
    a: tuple[int, ...], b: list[int]
) -> tuple[list[int], list[int], list[int]]:
    """Return the common 48x19 block, a left-null basis, and 12 targets."""
    matrix_rows = []
    for ai in range(6):
        for bj in range(8):
            matrix_rows.append(
                sum(
                    1 << term
                    for term in range(19)
                    if ((a[term] >> ai) & 1) and ((b[term] >> bj) & 1)
                )
            )
    basis: dict[int, tuple[int, int]] = {}
    dependencies = []
    for row_index, variables in enumerate(matrix_rows):
        provenance = 1 << row_index
        while variables:
            pivot = variables.bit_length() - 1
            if pivot not in basis:
                basis[pivot] = variables, provenance
                break
            old_variables, old_provenance = basis[pivot]
            variables ^= old_variables
            provenance ^= old_provenance
        else:
            dependencies.append(provenance)
    assert len(dependencies) == 48 - len(basis)

    targets = []
    for cbit in range(12):
        kc, ic = divmod(cbit, 3)
        target = 0
        for ai in range(6):
            i, j = divmod(ai, 2)
            for bj in range(8):
                jb, k = divmod(bj, 4)
                if j == jb and k == kc and i == ic:
                    target |= 1 << (ai * 8 + bj)
        targets.append(target)
    return matrix_rows, dependencies, targets


def block_columns(
    a: tuple[int, ...], rank_one_b: tuple[int, ...]
) -> list[list[int]]:
    result = []
    for avalue in a:
        by_b = []
        for bvalue in rank_one_b:
            column = 0
            for ai in range(6):
                if not ((avalue >> ai) & 1):
                    continue
                for bj in range(8):
                    if (bvalue >> bj) & 1:
                        column |= 1 << (ai * 8 + bj)
            by_b.append(column)
        result.append(by_b)
    return result


def block_score(witness: int, columns: list[list[int]]) -> tuple[float, tuple[int, ...]]:
    sizes = tuple(
        sum(not ((witness & column).bit_count() & 1) for column in term_columns)
        for term_columns in columns
    )
    assert all(sizes)
    return sum(math.log2(size) for size in sizes), sizes


def optimized_block_witnesses(
    a: tuple[int, ...],
    b: list[int],
    rank_one_b: tuple[int, ...],
    restarts: int,
    rng: random.Random,
) -> tuple[list[int], int, int]:
    """Coordinate-descent search in the exact 48-row left-null cosets."""
    _, dependencies, targets = block_system(a, b)
    columns = block_columns(a, rank_one_b)
    result = []
    starts_checked = 0
    improvements = 0
    for cbit, target in enumerate(targets):
        rhs = [(dependency & target).bit_count() & 1 for dependency in dependencies]
        if not any(rhs):
            continue
        pivot = next(
            dependency for dependency, value in zip(dependencies, rhs) if value
        )
        homogeneous = [
            dependency
            for dependency, value in zip(dependencies, rhs)
            if not value
        ] + [
            pivot ^ dependency
            for dependency, value in zip(dependencies, rhs)
            if value and dependency != pivot
        ]
        assert len(homogeneous) == len(dependencies) - 1
        starts = [
            dependency
            for dependency, value in zip(dependencies, rhs)
            if value
        ]
        for _ in range(restarts):
            witness = pivot
            for homogeneous_witness in homogeneous:
                if rng.getrandbits(1):
                    witness ^= homogeneous_witness
            starts.append(witness)
        for witness in starts:
            starts_checked += 1
            score, _ = block_score(witness, columns)
            changed = True
            while changed:
                changed = False
                for homogeneous_witness in homogeneous:
                    candidate = witness ^ homogeneous_witness
                    candidate_score, _ = block_score(candidate, columns)
                    if candidate_score > score + 1e-12:
                        witness = candidate
                        score = candidate_score
                        improvements += 1
                        changed = True
            result.append(lift_block_witness(witness, cbit))
    return result, starts_checked, improvements


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("model", type=Path)
    parser.add_argument("cut_output", type=Path)
    parser.add_argument("witness_output", type=Path)
    parser.add_argument("--missing", nargs=2, type=int, required=True)
    parser.add_argument("--fixed-b", type=int)
    parser.add_argument("--max-cuts", type=int, default=1)
    parser.add_argument(
        "--affine-samples", type=int, default=0,
        help="sample extra yT=1 points in the full left-null affine space",
    )
    parser.add_argument(
        "--block-restarts", type=int, default=0,
        help="48x19 block-coset coordinate-descent restarts per target slice",
    )
    parser.add_argument("--seed", type=int)
    args = parser.parse_args()

    missing = tuple(args.missing)
    assert missing in ((1, 2), (1, 4), (1, 8))
    a = tuple(value for value in RANK_ONE_A if value not in missing)
    assert len(a) == len(set(a)) == 19
    rank_one_b = tuple(
        value
        for value in range(1, 256)
        if rank_rows([value & 15, value >> 4], 4) == 1
    )
    assert len(rank_one_b) == 45
    bindex = {value: index for index, value in enumerate(rank_one_b)}
    positive = parse_model(args.model)
    b = []
    for term in range(19):
        selected = [
            value
            for offset, value in enumerate(rank_one_b)
            if term * 45 + offset + 1 in positive
        ]
        assert len(selected) == 1, (term, selected)
        b.append(selected[0])
    if args.fixed_b is not None:
        canonical_a = {(1, 2): 3, (1, 4): 5, (1, 8): 15}[missing]
        assert b[a.index(canonical_a)] == args.fixed_b

    rows = equations(a, b)
    dependencies = all_dependencies(rows)
    direct_witnesses = [witness for witness, rhs in dependencies if rhs]
    assert direct_witnesses, "the supplied B assignment has a consistent C system"
    _, block_dependencies, block_targets = block_system(a, b)
    block_direct = [
        lift_block_witness(dependency, cbit)
        for cbit, target in enumerate(block_targets)
        for dependency in block_dependencies
        if (dependency & target).bit_count() & 1
    ]
    # The 576-row system is exactly twelve permuted copies of this block.
    assert set(block_direct) == set(direct_witnesses)
    candidate_witnesses = list(direct_witnesses)
    seed_material = (
        f"{missing}|{args.fixed_b}|" + ",".join(map(str, b))
    ).encode()
    seed = (
        int.from_bytes(hashlib.sha256(seed_material).digest()[:8], "big")
        if args.seed is None
        else args.seed
    )
    if args.affine_samples:
        base = direct_witnesses[0]
        homogeneous = [
            witness for witness, rhs in dependencies if not rhs
        ] + [base ^ witness for witness in direct_witnesses[1:]]
        assert homogeneous
        rng = random.Random(seed)
        for _ in range(args.affine_samples):
            witness = base
            for _ in range(1 + rng.randrange(12)):
                witness ^= rng.choice(homogeneous)
            candidate_witnesses.append(witness)
    block_candidates = []
    block_starts = 0
    block_improvements = 0
    if args.block_restarts:
        block_candidates, block_starts, block_improvements = optimized_block_witnesses(
            a,
            b,
            rank_one_b,
            args.block_restarts,
            random.Random(seed ^ 0x324B10C),
        )
        candidate_witnesses.extend(block_candidates)

    columns = column_masks(a, rank_one_b)
    candidates = []
    seen_witnesses = set()
    for witness in candidate_witnesses:
        if witness in seen_witnesses:
            continue
        seen_witnesses.add(witness)
        selected_equations = [
            index for index in range(576) if (witness >> index) & 1
        ]
        assert selected_equations
        combined_row = 0
        combined_rhs = 0
        for index in selected_equations:
            combined_row ^= rows[index][0]
            combined_rhs ^= rows[index][1]
        assert combined_row == 0 and combined_rhs == 1

        allowed = []
        for term, _ in enumerate(a):
            term_allowed = []
            for offset, bvalue in enumerate(rank_one_b):
                if all(
                    not ((witness & columns[term][offset][cbit]).bit_count() & 1)
                    for cbit in range(12)
                ):
                    term_allowed.append(bvalue)
                    assert all(
                        not ((witness & columns[term][offset][cbit]).bit_count() & 1)
                        for cbit in range(12)
                    )
            assert b[term] in term_allowed
            allowed.append(term_allowed)

        outside_variables = [
            term * 45 + bindex[bvalue] + 1
            for term in range(19)
            for bvalue in rank_one_b
            if bvalue not in set(allowed[term])
        ]
        assert outside_variables
        cut = (
            " ".join(f"+1 x{variable}" for variable in outside_variables)
            + " >= 1 ;"
        )
        score = sum(math.log2(len(values)) for values in allowed)
        candidates.append(
            (
                -score,
                len(outside_variables),
                cut,
                {
                    "selected_equations": selected_equations,
                    "selected_equation_count": len(selected_equations),
                    "allowed_B_by_term": allowed,
                    "allowed_sizes": list(map(len, allowed)),
                    "cut_sha256": hashlib.sha256((cut + "\n").encode()).hexdigest(),
                    "cut_literals": len(outside_variables),
                    "excluded_log2_cartesian_size": score,
                    "direct_column_audit": "PASS",
                    "combined_row": 0,
                    "combined_rhs": 1,
                },
            )
        )

    # Multiple dependencies can induce the same semantic one-hot clause.
    candidates.sort(key=lambda candidate: candidate[:3])
    unique = []
    seen_cuts = set()
    for _, _, cut, metadata in candidates:
        if cut in seen_cuts:
            continue
        seen_cuts.add(cut)
        unique.append((cut, metadata))
    selected = unique[: args.max_cuts]
    assert selected
    args.cut_output.write_text("".join(cut + "\n" for cut, _ in selected))
    witness_data = {
        "missing_A": list(missing),
        "fixed_B": args.fixed_b,
        "B_assignment": b,
        "gaussian_dependencies": len(dependencies),
        "dependency_witnesses": len(direct_witnesses),
        "affine_samples": args.affine_samples,
        "block_restarts": args.block_restarts,
        "block_candidates": len(block_candidates),
        "block_starts": block_starts,
        "block_improvements": block_improvements,
        "block_equivalence_audit": "PASS",
        "candidate_witnesses": len(seen_witnesses),
        "unique_cuts": len(seen_cuts),
        "selected_cuts": [metadata for _, metadata in selected],
    }
    args.witness_output.write_text(json.dumps(witness_data, indent=2) + "\n")
    print(
        f"dependency_witnesses={len(direct_witnesses)} "
        f"affine_samples={args.affine_samples} candidate_witnesses={len(seen_witnesses)} "
        f"block_restarts={args.block_restarts} block_candidates={len(block_candidates)} "
        f"selected_cuts={len(selected)} "
        f"best_equations={selected[0][1]['selected_equation_count']} "
        f"best_allowed_sizes={','.join(map(str, selected[0][1]['allowed_sizes']))} "
        f"best_cut_literals={selected[0][1]['cut_literals']}"
    )


if __name__ == "__main__":
    main()
