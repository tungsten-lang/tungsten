#!/usr/bin/env python3
"""Independent checker for serialized n324 residual-symmetry cut lifts."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from fixed_a_shards import left_b, right_b
from n324_common import RANK_ONE_A, apply_a, gl_packed, inverse_square, rank_rows


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while chunk := source.read(1 << 20):
            digest.update(chunk)
    return digest.hexdigest()


def row_times(value: int, matrix: int, width: int) -> int:
    result = 0
    mask = (1 << width) - 1
    for row in range(width):
        if (value >> row) & 1:
            result ^= (matrix >> (width * row)) & mask
    return result


def multiply(first: int, second: int, width: int) -> int:
    mask = (1 << width) - 1
    return sum(
        row_times((first >> (width * row)) & mask, second, width)
        << (width * row)
        for row in range(width)
    )


def identity(width: int) -> int:
    return sum(1 << (width * row + row) for row in range(width))


def compose(first, second):
    left1, right1, shared1 = first
    left2, right2, shared2 = second
    return (
        multiply(left2, left1, 3),
        multiply(right1, right2, 2),
        multiply(shared1, shared2, 4),
    )


def closure(generators):
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


def outer_mask(a: int, b: int, c: int) -> int:
    result = 0
    for ai in range(6):
        if (a >> ai) & 1:
            for bj in range(8):
                if (b >> bj) & 1:
                    for ck in range(12):
                        if (c >> ck) & 1:
                            result |= 1 << ((ai * 8 + bj) * 12 + ck)
    return result


def build_columns(a, bvalues):
    return [
        [
            [outer_mask(avalue, bvalue, 1 << cbit) for cbit in range(12)]
            for bvalue in bvalues
        ]
        for avalue in a
    ]


def allowed_signature(witness: int, columns) -> tuple[int, ...]:
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
    return " ".join(f"+1 x{variable}" for variable in variables) + " >= 1 ;"


def transform_mask(mask: int, permutation: tuple[int, ...]) -> int:
    result = 0
    while mask:
        bit = mask & -mask
        result |= 1 << permutation[bit.bit_length() - 1]
        mask -= bit
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    data = json.loads(args.manifest.read_text())
    assert data["schema"] == "n324-benders-orbit-lift-v1"
    missing = tuple(data["missing_A"])
    a = tuple(value for value in RANK_ONE_A if value not in missing)
    aindex = {value: index for index, value in enumerate(a)}
    bvalues = tuple(
        value
        for value in range(1, 256)
        if rank_rows([value & 15, value >> 4], 4) == 1
    )
    bindex = {value: index for index, value in enumerate(bvalues)}
    columns = build_columns(a, bvalues)
    generators = [tuple(element) for element in data["selected_generators"]]
    # Re-enumerate the complete residual group rather than trusting the
    # generator's reported order.
    full_group = set()
    gl4 = gl_packed(4)
    for left in gl_packed(3):
        for right in gl_packed(2):
            if {apply_a(value, left, right) for value in missing} != set(missing):
                continue
            if apply_a(data["canonical_A"], left, right) != data["canonical_A"]:
                continue
            transformed_b = left_b(inverse_square(right, 2), data["fixed_B"])
            for shared in gl4:
                if right_b(transformed_b, shared) == data["fixed_B"]:
                    full_group.add((left, right, shared))
    assert len(full_group) == data["full_residual_group_order"]
    assert set(generators) <= full_group
    subgroup = closure(generators)
    assert len(subgroup) == data["selected_subgroup_order"]
    for left, right, shared in subgroup:
        assert {apply_a(value, left, right) for value in missing} == set(missing)
        assert apply_a(data["canonical_A"], left, right) == data["canonical_A"]
        transformed_b = right_b(
            left_b(inverse_square(right, 2), data["fixed_B"]), shared
        )
        assert transformed_b == data["fixed_B"]

    cut_path = Path(data["cut_file"])
    witness_path = Path(data["witness_file"])
    assert sha256(cut_path) == data["cut_file_sha256"]
    assert sha256(witness_path) == data["witness_file_sha256"]
    lines = cut_path.read_text().splitlines()
    records = [json.loads(line) for line in witness_path.read_text().splitlines()]
    assert len(lines) == len(records) == data["lifted_unique_cuts"]
    target = 0
    for ai in range(6):
        i, j = divmod(ai, 2)
        for bj in range(8):
            jb, k = divmod(bj, 4)
            for ck in range(12):
                kc, ic = divmod(ck, 3)
                if j == jb and k == kc and i == ic:
                    target |= 1 << ((ai * 8 + bj) * 12 + ck)

    signatures = set()
    for line, record in zip(lines, records):
        witness = int(record["y_hex"], 16)
        signature = tuple(int(mask, 16) for mask in record["allowed_masks_hex"])
        assert len(signature) == 19
        assert (witness & target).bit_count() & 1
        assert allowed_signature(witness, columns) == signature
        expected = cut_line(signature)
        assert line == expected
        assert record["cut_sha256"] == hashlib.sha256((line + "\n").encode()).hexdigest()
        assert signature not in signatures
        signatures.add(signature)

    # Reparse every direct archive witness and prove it is present.
    archive_manifest = Path(data["archive_manifest"])
    assert sha256(archive_manifest) == data["archive_manifest_sha256"]
    archive_dir = archive_manifest.parent
    recorded_inputs = {
        item["name"]: item["sha256"] for item in data["input_witness_files"]
    }
    actual_inputs = sorted(archive_dir.glob("cuts[0-9][0-9][0-9].json"))
    assert set(recorded_inputs) == {path.name for path in actual_inputs}
    assert all(sha256(path) == recorded_inputs[path.name] for path in actual_inputs)
    direct = set()
    for path in actual_inputs:
        item_data = json.loads(path.read_text())
        for item in item_data["selected_cuts"]:
            direct.add(
                tuple(
                    sum(1 << bindex[value] for value in allowed)
                    for allowed in item["allowed_B_by_term"]
                )
            )
    assert len(direct) == data["direct_unique_cuts"]
    assert direct <= signatures

    # Independently prove closure of every serialized clause under generators.
    for left, right, shared in generators:
        term_permutation = tuple(
            aindex[apply_a(value, left, right)] for value in a
        )
        b_permutation = tuple(
            bindex[right_b(left_b(inverse_square(right, 2), value), shared)]
            for value in bvalues
        )
        for signature in signatures:
            transformed = [0] * 19
            for source, mask in enumerate(signature):
                transformed[term_permutation[source]] = transform_mask(
                    mask, b_permutation
                )
            assert tuple(transformed) in signatures
    print(
        f"ORBIT_LIFT PASS full_group={len(full_group)} subgroup={len(subgroup)} "
        f"direct={len(direct)} "
        f"lifted={len(signatures)} all_y_allowed_cut_and_closure=PASS"
    )


if __name__ == "__main__":
    main()
