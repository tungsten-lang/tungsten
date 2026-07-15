#!/usr/bin/env python3
"""Orbit-lift audited n324 Benders cuts under a residual shard subgroup."""

from __future__ import annotations

import argparse
import collections
import hashlib
import json
from pathlib import Path

from fixed_a_shards import left_b, left_c, right_b, right_c
from n324_common import (
    RANK_ONE_A,
    apply_a,
    gl_packed,
    inverse_square,
    rank_rows,
)
from rankone_ab_shards import closure, group_generators


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def rank_one_b_values() -> tuple[int, ...]:
    values = tuple(
        value
        for value in range(1, 256)
        if rank_rows([value & 15, value >> 4], 4) == 1
    )
    assert len(values) == 45
    return values


def residual_group(
    missing: tuple[int, int], canonical_a: int, fixed_b: int
) -> list[tuple[int, int, int]]:
    """Full group preserving the A support, canonical A, and fixed B."""
    gl4 = gl_packed(4)
    result = []
    for left in gl_packed(3):
        for right in gl_packed(2):
            if {apply_a(value, left, right) for value in missing} != set(missing):
                continue
            if apply_a(canonical_a, left, right) != canonical_a:
                continue
            transformed_b = left_b(inverse_square(right, 2), fixed_b)
            for shared in gl4:
                if right_b(transformed_b, shared) == fixed_b:
                    result.append((left, right, shared))
    assert len(result) == len(set(result))
    return sorted(result)


def outer_mask(a: int, b: int, c: int) -> int:
    result = 0
    for ai in range(6):
        if not ((a >> ai) & 1):
            continue
        for bj in range(8):
            if not ((b >> bj) & 1):
                continue
            for ck in range(12):
                if (c >> ck) & 1:
                    result |= 1 << ((ai * 8 + bj) * 12 + ck)
    return result


def action(
    element: tuple[int, int, int],
    a: tuple[int, ...],
    bvalues: tuple[int, ...],
) -> tuple[tuple[int, ...], tuple[int, ...], tuple[int, ...]]:
    """Return term permutation, B permutation, and dual y output masks."""
    left, right, shared = element
    left_inverse = inverse_square(left, 3)
    right_inverse = inverse_square(right, 2)
    shared_inverse = inverse_square(shared, 4)
    aindex = {value: index for index, value in enumerate(a)}
    bindex = {value: index for index, value in enumerate(bvalues)}
    term_permutation = tuple(
        aindex[apply_a(value, left, right)] for value in a
    )
    b_permutation = tuple(
        bindex[right_b(left_b(right_inverse, value), shared)]
        for value in bvalues
    )

    # y' = T^{-T} y.  For output coordinate o, dual_masks[o] is
    # T^{-1}(e_o), so y'_o is its parity pairing with y.
    inverse_a = [
        apply_a(1 << ai, left_inverse, right_inverse) for ai in range(6)
    ]
    inverse_b = [
        right_b(left_b(right, 1 << bj), shared_inverse) for bj in range(8)
    ]
    inverse_c = [
        right_c(left_c(shared, 1 << ck), left) for ck in range(12)
    ]
    dual_masks = tuple(
        outer_mask(inverse_a[ai], inverse_b[bj], inverse_c[ck])
        for ai in range(6)
        for bj in range(8)
        for ck in range(12)
    )
    assert len(set(term_permutation)) == 19
    assert len(set(b_permutation)) == 45
    assert len(dual_masks) == 576
    return term_permutation, b_permutation, dual_masks


def transform_mask(mask: int, permutation: tuple[int, ...]) -> int:
    result = 0
    while mask:
        bit = mask & -mask
        result |= 1 << permutation[bit.bit_length() - 1]
        mask -= bit
    return result


def transform_signature(
    signature: tuple[int, ...],
    term_permutation: tuple[int, ...],
    b_permutation: tuple[int, ...],
) -> tuple[int, ...]:
    result = [0] * 19
    for source, mask in enumerate(signature):
        result[term_permutation[source]] = transform_mask(mask, b_permutation)
    return tuple(result)


def transform_witness(witness: int, dual_masks: tuple[int, ...]) -> int:
    return sum(
        1 << output
        for output, mask in enumerate(dual_masks)
        if (witness & mask).bit_count() & 1
    )


def column_masks(
    a: tuple[int, ...], bvalues: tuple[int, ...]
) -> list[list[list[int]]]:
    result = []
    for avalue in a:
        by_b = []
        for bvalue in bvalues:
            by_b.append(
                [outer_mask(avalue, bvalue, 1 << cbit) for cbit in range(12)]
            )
        result.append(by_b)
    return result


def allowed_signature(witness: int, columns: list[list[list[int]]]) -> tuple[int, ...]:
    result = []
    for term in range(19):
        allowed = 0
        for offset in range(45):
            if all(
                not ((witness & columns[term][offset][cbit]).bit_count() & 1)
                for cbit in range(12)
            ):
                allowed |= 1 << offset
        result.append(allowed)
    return tuple(result)


def cut_line(signature: tuple[int, ...]) -> str:
    variables = [
        term * 45 + offset + 1
        for term, allowed in enumerate(signature)
        for offset in range(45)
        if not ((allowed >> offset) & 1)
    ]
    assert variables
    return " ".join(f"+1 x{variable}" for variable in variables) + " >= 1 ;"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive_dir", type=Path)
    parser.add_argument("cut_output", type=Path)
    parser.add_argument("witness_output", type=Path)
    parser.add_argument("manifest_output", type=Path)
    parser.add_argument("--missing", nargs=2, type=int, required=True)
    parser.add_argument("--fixed-b", type=int, required=True)
    parser.add_argument("--generator-count", type=int, default=2)
    parser.add_argument("--max-cuts", type=int, default=30000)
    args = parser.parse_args()

    missing = tuple(args.missing)
    canonical_a = {(1, 2): 3, (1, 4): 5, (1, 8): 15}[missing]
    a = tuple(value for value in RANK_ONE_A if value not in missing)
    assert len(a) == 19 and canonical_a in a
    bvalues = rank_one_b_values()
    bindex = {value: index for index, value in enumerate(bvalues)}

    full_group = residual_group(missing, canonical_a, args.fixed_b)
    full_generators = group_generators(full_group)
    assert 1 <= args.generator_count <= len(full_generators)
    selected_generators = full_generators[: args.generator_count]
    subgroup = closure(selected_generators)
    actions = [action(element, a, bvalues) for element in selected_generators]

    witnesses: dict[tuple[int, ...], int] = {}
    input_json = sorted(args.archive_dir.glob("cuts[0-9][0-9][0-9].json"))
    assert input_json
    for path in input_json:
        data = json.loads(path.read_text())
        assert data["missing_A"] == list(missing)
        assert data["fixed_B"] == args.fixed_b
        for item in data["selected_cuts"]:
            signature = tuple(
                sum(1 << bindex[value] for value in allowed)
                for allowed in item["allowed_B_by_term"]
            )
            witness = sum(1 << index for index in item["selected_equations"])
            witnesses.setdefault(signature, witness)
    direct_count = len(witnesses)

    queue = collections.deque(witnesses)
    while queue:
        signature = queue.popleft()
        witness = witnesses[signature]
        for term_permutation, b_permutation, dual_masks in actions:
            transformed_signature = transform_signature(
                signature, term_permutation, b_permutation
            )
            if transformed_signature in witnesses:
                continue
            transformed_witness = transform_witness(witness, dual_masks)
            witnesses[transformed_signature] = transformed_witness
            queue.append(transformed_signature)
            assert len(witnesses) <= args.max_cuts, (
                "orbit cap exceeded; select a smaller subgroup",
                len(witnesses),
            )

    columns = column_masks(a, bvalues)
    target = 0
    for ai in range(6):
        i, j = divmod(ai, 2)
        for bj in range(8):
            jb, k = divmod(bj, 4)
            for ck in range(12):
                kc, ic = divmod(ck, 3)
                if j == jb and k == kc and i == ic:
                    target |= 1 << ((ai * 8 + bj) * 12 + ck)

    records = []
    lines = []
    for signature in sorted(witnesses):
        witness = witnesses[signature]
        assert (witness & target).bit_count() & 1
        assert allowed_signature(witness, columns) == signature
        line = cut_line(signature)
        digest = hashlib.sha256((line + "\n").encode()).hexdigest()
        lines.append(line)
        records.append(
            {
                "y_hex": format(witness, "0144x"),
                "allowed_masks_hex": [format(mask, "012x") for mask in signature],
                "cut_sha256": digest,
            }
        )

    args.cut_output.write_text("\n".join(lines) + "\n")
    with args.witness_output.open("w") as sink:
        for record in records:
            sink.write(json.dumps(record, separators=(",", ":")) + "\n")
    archive_manifest = args.archive_dir / "manifest.json"
    assert archive_manifest.is_file()
    manifest = {
        "schema": "n324-benders-orbit-lift-v1",
        "claim_scope": "sound symmetry cuts only; not an UNSAT proof",
        "missing_A": list(missing),
        "canonical_A": canonical_a,
        "fixed_B": args.fixed_b,
        "full_residual_group_order": len(full_group),
        "full_generator_count": len(full_generators),
        "selected_generators": [list(element) for element in selected_generators],
        "selected_subgroup_order": len(subgroup),
        "direct_unique_cuts": direct_count,
        "lifted_unique_cuts": len(witnesses),
        "archive_manifest": str(archive_manifest.resolve()),
        "archive_manifest_sha256": sha256(archive_manifest),
        "cut_file": str(args.cut_output.resolve()),
        "cut_file_sha256": sha256(args.cut_output),
        "witness_file": str(args.witness_output.resolve()),
        "witness_file_sha256": sha256(args.witness_output),
        "input_witness_files": [
            {"name": path.name, "sha256": sha256(path)} for path in input_json
        ],
        "validation": {
            "target_pairing_one": "PASS",
            "allowed_tables_recomputed": "PASS",
            "cut_lines_rebuilt": "PASS",
            "subgroup_orbit_closure": "PASS",
        },
    }
    args.manifest_output.write_text(json.dumps(manifest, indent=2) + "\n")
    print(
        f"full_group={len(full_group)} full_generators={len(full_generators)} "
        f"subgroup={len(subgroup)} direct={direct_count} lifted={len(witnesses)} "
        f"cuts_sha256={sha256(args.cut_output)} "
        f"witnesses_sha256={sha256(args.witness_output)}"
    )


if __name__ == "__main__":
    main()
