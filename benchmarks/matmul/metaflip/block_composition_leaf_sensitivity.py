#!/usr/bin/env python3
"""Rank block-composition leaves by one-rank downstream sensitivity.

The calculation uses the exact rank-47 4x4 outer support and the stored
allocation of each recipe.  Effective leaf shapes are canonicalized across
all six S3 tensor orientations.  Before reporting anything, the script
reconstructs each recipe's formula rank from the checked-in complete 2..8 leaf
pool; it aborts if a manifest, audit row, outer, or production leaf has
drifted.
"""

from __future__ import annotations

import argparse
import csv
from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path
import re
from typing import Iterable


HERE = Path(__file__).resolve().parent
OUTER_PATH = HERE / "matmul_4x4_rank47_d450_gf2.txt"
POOL_SOURCE = HERE / "flipfleet_block_formula_scan_cross.w"
SAVED_PATH = HERE / "block_composition_opportunities.tsv"
MANIFEST_PATH = HERE / "block_composition_records.tsv"
AUDIT_PATH = HERE / "block_composition_cross_audit.tsv"
SMALL_CROSS_AUDIT_PATH = HERE / "block_composition_small_cross_audit.tsv"


Shape = tuple[int, int, int]


@dataclass
class Sensitivity:
    occurrences: int = 0
    formulas: int = 0
    guaranteed_records: int = 0
    guaranteed_margin: int = 0
    shadow_records: int = 0
    orientations: Counter[Shape] = field(default_factory=Counter)


def read_tsv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def scheme_rank(path: Path) -> int:
    lines = [line for line in path.read_text().splitlines() if line.strip()]
    if not lines:
        raise ValueError(f"empty scheme: {path}")
    first = lines[0].split()
    if first[0] == "R":
        if any(line.split()[0] != "R" for line in lines):
            raise ValueError(f"mixed R-line scheme: {path}")
        return len(lines)
    return int(first[0])


def composition_leaf_ranks() -> dict[Shape, int]:
    pattern = re.compile(
        r'ffbc_cross_scan_add\(root, "([^"]+)", (\d+), (\d+), (\d+), leaves\)'
    )
    ranks: dict[Shape, int] = {}
    for relative, n, m, p in pattern.findall(POOL_SOURCE.read_text()):
        shape = tuple(sorted((int(n), int(m), int(p))))
        rank = scheme_rank(HERE / relative)
        if shape in ranks:
            raise ValueError(f"duplicate production leaf shape: {shape}")
        ranks[shape] = rank
    if len(ranks) != 56:
        raise ValueError(f"expected complete 3..8 leaf pool of 56 shapes, got {len(ranks)}")

    small_leaves = (
        ((2, 2, 2), "matmul_2x2_rank7_strassen_gf2.txt"),
        ((2, 2, 3), "matmul_2x2x3_rank11_catalog_gf2.txt"),
        ((2, 2, 4), "matmul_2x2x4_rank14_strassen_blocks_gf2.txt"),
        ((2, 2, 5), "matmul_2x2x5_rank18_blocks_gf2.txt"),
        ((2, 2, 6), "matmul_2x2x6_rank21_strassen_blocks_gf2.txt"),
        ((2, 2, 7), "matmul_2x2x7_rank25_catalog_gf2.txt"),
        ((2, 2, 8), "matmul_2x2x8_rank28_catalog_gf2.txt"),
        ((2, 3, 3), "matmul_2x3x3_rank15_catalog_gf2.txt"),
        ((2, 3, 4), "matmul_2x3x4_rank20_catalog_gf2.txt"),
        ((2, 3, 5), "matmul_2x3x5_rank25_d160_fleet_gf2.txt"),
        ((2, 3, 6), "matmul_2x3x6_rank30_catalog_gf2.txt"),
        ((2, 3, 7), "matmul_2x3x7_rank35_catalog_gf2.txt"),
        ((2, 3, 8), "matmul_2x3x8_rank40_catalog_gf2.txt"),
        ((2, 4, 4), "matmul_2x4x4_rank26_catalog_gf2.txt"),
        ((2, 4, 5), "matmul_2x4x5_rank33_catalog_gf2.txt"),
        ((2, 4, 6), "matmul_2x4x6_rank39_catalog_gf2.txt"),
        ((2, 4, 7), "matmul_2x4x7_rank45_catalog_gf2.txt"),
        ((2, 4, 8), "matmul_2x4x8_rank51_catalog_gf2.txt"),
        ((2, 5, 5), "matmul_2x5x5_rank40_catalog_gf2.txt"),
        ((2, 5, 6), "matmul_2x5x6_rank47_catalog_gf2.txt"),
        ((2, 5, 7), "matmul_2x5x7_rank55_catalog_gf2.txt"),
        ((2, 5, 8), "matmul_2x5x8_rank63_catalog_gf2.txt"),
        ((2, 6, 6), "matmul_2x6x6_rank56_catalog_gf2.txt"),
        ((2, 6, 7), "matmul_2x6x7_rank66_catalog_gf2.txt"),
        ((2, 6, 8), "matmul_2x6x8_rank75_catalog_gf2.txt"),
        ((2, 7, 7), "matmul_2x7x7_rank76_catalog_gf2.txt"),
        ((2, 7, 8), "matmul_2x7x8_rank88_catalog_gf2.txt"),
        ((2, 8, 8), "matmul_2x8x8_rank100_catalog_gf2.txt"),
    )
    for shape, filename in small_leaves:
        if shape in ranks:
            raise ValueError(f"duplicate small-block leaf shape: {shape}")
        ranks[shape] = scheme_rank(HERE / filename)
    if len(ranks) != 84:
        raise ValueError(f"expected 84 composition leaf shapes, got {len(ranks)}")
    return ranks


def outer_terms() -> list[tuple[int, int, int]]:
    terms: list[tuple[int, int, int]] = []
    for line in OUTER_PATH.read_text().splitlines():
        fields = line.split()
        if len(fields) != 4 or fields[0] != "R":
            raise ValueError(f"malformed rank-47 outer line: {line!r}")
        terms.append((int(fields[1]), int(fields[2]), int(fields[3])))
    if len(terms) != 47:
        raise ValueError(f"expected rank-47 outer, got {len(terms)} terms")
    return terms


def allocation(row: dict[str, str], key: str) -> tuple[int, int, int, int]:
    values = tuple(int(value) for value in row[key].split(","))
    if len(values) != 4:
        raise ValueError(f"{row['target']} has non-four-way {key}: {values}")
    return values  # type: ignore[return-value]


def extent(
    mask: int,
    row_allocation: tuple[int, int, int, int],
    column_allocation: tuple[int, int, int, int],
) -> tuple[int, int]:
    row_extent = 0
    column_extent = 0
    for i in range(4):
        for j in range(4):
            if (mask >> (i * 4 + j)) & 1:
                row_extent = max(row_extent, row_allocation[i])
                column_extent = max(column_extent, column_allocation[j])
    return row_extent, column_extent


def recipe_shapes(
    row: dict[str, str], terms: Iterable[tuple[int, int, int]]
) -> Counter[Shape]:
    alloc_n = allocation(row, "alloc_n")
    alloc_m = allocation(row, "alloc_m")
    alloc_p = allocation(row, "alloc_p")
    result: Counter[Shape] = Counter()
    for u_mask, v_mask, w_mask in terms:
        ue = extent(u_mask, alloc_n, alloc_m)
        ve = extent(v_mask, alloc_m, alloc_p)
        we = extent(w_mask, alloc_n, alloc_p)
        oriented = (
            min(ue[0], we[0]),
            min(ue[1], ve[0]),
            min(ve[1], we[1]),
        )
        if min(oriented) < 1:
            raise ValueError(f"{row['target']} induces zero leaf {oriented}")
        result[oriented] += 1
    return result


def validate_formula(
    row: dict[str, str], shapes: Counter[Shape], ranks: dict[Shape, int]
) -> None:
    computed = sum(ranks[tuple(sorted(shape))] * count for shape, count in shapes.items())
    expected = int(row["formula_rank"])
    if computed != expected:
        raise ValueError(
            f"{row['target']} formula drift: stored {expected}, reconstructed {computed}"
        )


def accumulate(
    rows: Iterable[dict[str, str]],
    ranks: dict[Shape, int],
    terms: list[tuple[int, int, int]],
    scope: str,
) -> dict[Shape, Sensitivity]:
    result: dict[Shape, Sensitivity] = {}
    for row in rows:
        oriented_counts = recipe_shapes(row, terms)
        validate_formula(row, oriented_counts, ranks)
        canonical_counts: Counter[Shape] = Counter()
        for oriented, count in oriented_counts.items():
            canonical_counts[tuple(sorted(oriented))] += count
        cancellation = 0
        if scope == "saved":
            cancellation = int(row["formula_rank"]) - int(row["exact_rank"])
        for shape, count in canonical_counts.items():
            item = result.setdefault(shape, Sensitivity())
            item.occurrences += count
            item.formulas += 1
            if scope == "saved":
                margin = count - cancellation
                if margin > 0:
                    item.guaranteed_records += 1
                    item.guaranteed_margin += margin
            else:
                item.guaranteed_records += 1
                item.guaranteed_margin += count
        for oriented, count in oriented_counts.items():
            result[tuple(sorted(oriented))].orientations[oriented] += count
    return result


def add_shadow_records(
    result: dict[Shape, Sensitivity],
    rows: Iterable[dict[str, str]],
    ranks: dict[Shape, int],
    terms: list[tuple[int, int, int]],
) -> None:
    for row in rows:
        if row["audited_gain"] == "":
            # No pinned GF(2) comparator: a one-rank leaf improvement remains
            # an upper-bound improvement, but cannot create a strict record.
            continue
        if int(row["audited_gain"]) > 0:
            continue
        oriented_counts = recipe_shapes(row, terms)
        validate_formula(row, oriented_counts, ranks)
        canonical_counts: Counter[Shape] = Counter()
        for oriented, count in oriented_counts.items():
            canonical_counts[tuple(sorted(oriented))] += count
        gain = int(row["audited_gain"])
        for shape, count in canonical_counts.items():
            if gain + count > 0:
                result.setdefault(shape, Sensitivity()).shadow_records += 1


def orientation_text(counts: Counter[Shape]) -> str:
    ordered = sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    return ";".join(f"{'x'.join(map(str, shape))}:{count}" for shape, count in ordered)


def emit(
    scope: str,
    result: dict[Shape, Sensitivity],
    ranks: dict[Shape, int],
    limit: int,
) -> None:
    rows = [
        (shape, item)
        for shape, item in result.items()
        if len(set(shape)) > 1 and item.occurrences > 0
    ]
    rows.sort(key=lambda pair: (-pair[1].occurrences, -pair[1].formulas, pair[0]))
    if limit > 0:
        rows = rows[:limit]
    for shape, item in rows:
        print(
            "\t".join(
                (
                    scope,
                    "x".join(map(str, shape)),
                    str(ranks[shape]),
                    str(item.occurrences),
                    str(item.formulas),
                    str(item.guaranteed_records),
                    str(item.guaranteed_margin),
                    str(item.shadow_records),
                    orientation_text(item.orientations),
                )
            )
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int, default=10, help="rows per scope; 0 means all")
    args = parser.parse_args()

    ranks = composition_leaf_ranks()
    terms = outer_terms()
    saved_rows = [
        row for row in read_tsv(SAVED_PATH) if row["materialized"] == "1"
    ]
    for row in saved_rows:
        row["exact_rank"] = row["exact_best_rank"]
    legacy_targets = {row["target"] for row in saved_rows}
    audit_rows = read_tsv(AUDIT_PATH)
    small_cross_rows = read_tsv(SMALL_CROSS_AUDIT_PATH)
    small_cross_by_target = {row["target"]: row for row in small_cross_rows}
    manifest_rows = read_tsv(MANIFEST_PATH)
    for manifest_row in manifest_rows:
        if manifest_row["target"] in legacy_targets:
            continue
        audit_row = dict(small_cross_by_target[manifest_row["target"]])
        # The balanced field audit supplies comparator metadata, but a saved
        # certificate may come from a better bounded allocation or a different
        # formula-minimizing tie.  Sensitivity must follow the materialized
        # manifest recipe, whose formula is independently recomputed below.
        for column in ("formula_rank", "alloc_n", "alloc_m", "alloc_p"):
            audit_row[column] = manifest_row[column]
        audit_row["exact_rank"] = manifest_row["exact_rank"]
        saved_rows.append(audit_row)
    for row in small_cross_rows:
        # Normalize the field-aware seam audit to the historical cross-band
        # interface used by the sensitivity accumulator.
        row["audited_gain"] = row["f2_gain"]
    audit_rows.extend(small_cross_rows)
    audited_rows = [
        row for row in audit_rows if int(row["audited_gain"] or "0") > 0
    ]
    if len(saved_rows) != len(manifest_rows) or len(audited_rows) != 889:
        raise ValueError(
            f"expected {len(manifest_rows)} saved and 889 audited formulas, got {len(saved_rows)} and {len(audited_rows)}"
        )

    saved = accumulate(saved_rows, ranks, terms, "saved")
    audited = accumulate(audited_rows, ranks, terms, "audited")
    add_shadow_records(audited, audit_rows, ranks, terms)

    print(
        "scope\tleaf\tleaf_rank\taggregate_rank_delta\tformulas_using_leaf\t"
        "guaranteed_records_improved\tguaranteed_exact_margin\t"
        "shadow_records_created\torientation_occurrences"
    )
    emit("saved", saved, ranks, args.limit)
    emit("audited", audited, ranks, args.limit)


if __name__ == "__main__":
    main()
