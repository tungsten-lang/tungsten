#!/usr/bin/env python3
"""Independently exact-check the published block-composition certificates.

This verifier does not import or invoke FlipFleet's Tungsten verifier.  For
each rank-one term it expands the U and V supports and XORs the complete W
mask into the corresponding (A, B) coefficient.  The resulting sparse parity
map must equal the matrix-multiplication tensor over GF(2) exactly.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import re
import time
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass
from pathlib import Path


CERTIFICATE_NAME = re.compile(
    r"^matmul_(\d+)x(\d+)(?:x(\d+))?_rank(\d+)_block47"
    r"(?:_(?:unbalanced|smallcross))?_gf2\.txt$"
)
MANIFEST_COLUMNS = (
    "target",
    "formula_rank",
    "exact_rank",
    "alloc_n",
    "alloc_m",
    "alloc_p",
    "certificate",
    "sha256",
)


@dataclass(frozen=True)
class Record:
    target: str
    dimensions: tuple[int, int, int]
    exact_rank: int
    certificate: str
    sha256: str


@dataclass(frozen=True)
class Result:
    target: str
    exact_rank: int
    certificate: str
    sha256: str
    terms: int
    pair_xors: int
    tensor_ones: int


def _dimensions(text: str) -> tuple[int, int, int]:
    parts = text.split("x")
    if len(parts) != 3 or any(not part.isdecimal() for part in parts):
        raise ValueError(f"invalid target dimensions: {text!r}")
    dimensions = tuple(int(part) for part in parts)
    if any(dimension <= 0 for dimension in dimensions):
        raise ValueError(f"non-positive target dimension: {text!r}")
    return dimensions  # type: ignore[return-value]


def _allocation(text: str) -> tuple[int, ...]:
    parts = text.split(",")
    if not parts or any(not part.isdecimal() for part in parts):
        raise ValueError(f"invalid block allocation: {text!r}")
    result = tuple(int(part) for part in parts)
    if any(part <= 0 for part in result):
        raise ValueError(f"non-positive block allocation: {text!r}")
    return result


def _filename_shape_and_rank(name: str) -> tuple[tuple[int, int, int], int]:
    match = CERTIFICATE_NAME.fullmatch(name)
    if match is None:
        raise ValueError(f"non-canonical certificate filename: {name!r}")
    first, second, third, rank = match.groups()
    if third is None:
        if first != second:
            raise ValueError(f"abbreviated filename is not square: {name!r}")
        dimensions = (int(first), int(first), int(first))
    else:
        dimensions = (int(first), int(second), int(third))
    return dimensions, int(rank)


def _read_manifest(path: Path) -> list[Record]:
    with path.open(newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if tuple(reader.fieldnames or ()) != MANIFEST_COLUMNS:
            raise ValueError(
                f"unexpected manifest columns: {reader.fieldnames!r}; "
                f"expected {MANIFEST_COLUMNS!r}"
            )
        rows = list(reader)

    if not rows:
        raise ValueError("manifest contains no certificate rows")

    targets: set[str] = set()
    canonical_targets: set[tuple[int, int, int]] = set()
    certificates: set[str] = set()
    records: list[Record] = []
    for line_number, row in enumerate(rows, start=2):
        target = row["target"]
        dimensions = _dimensions(target)
        canonical_target = tuple(sorted(dimensions))
        if dimensions != canonical_target:
            raise ValueError(
                f"line {line_number}: target is not in canonical sorted order: "
                f"{target}"
            )
        try:
            formula_rank = int(row["formula_rank"])
            exact_rank = int(row["exact_rank"])
        except ValueError as error:
            raise ValueError(f"line {line_number}: non-integral rank") from error
        if formula_rank <= 0 or exact_rank <= 0 or exact_rank > formula_rank:
            raise ValueError(
                f"line {line_number}: inconsistent formula/exact ranks "
                f"{formula_rank}/{exact_rank}"
            )

        # Recipes are retained in the source tensor's orientation, while the
        # target and certificate are canonicalized through an S3 permutation.
        # Their three totals must therefore agree as a multiset, not always
        # axis by axis.
        allocations = tuple(
            _allocation(row[column]) for column in ("alloc_n", "alloc_m", "alloc_p")
        )
        allocation_totals = tuple(sum(allocation) for allocation in allocations)
        if sorted(allocation_totals) != sorted(dimensions):
            raise ValueError(
                f"line {line_number}: allocation totals {allocation_totals} do "
                f"not describe target {dimensions} under any S3 orientation"
            )

        certificate = row["certificate"]
        file_dimensions, file_rank = _filename_shape_and_rank(certificate)
        if file_dimensions != dimensions or file_rank != exact_rank:
            raise ValueError(
                f"line {line_number}: filename describes {file_dimensions} rank "
                f"{file_rank}, manifest says {dimensions} rank {exact_rank}"
            )

        digest = row["sha256"]
        if re.fullmatch(r"[0-9a-f]{64}", digest) is None:
            raise ValueError(f"line {line_number}: invalid SHA-256 digest")
        if target in targets:
            raise ValueError(f"line {line_number}: duplicate target {target}")
        if canonical_target in canonical_targets:
            raise ValueError(
                f"line {line_number}: S3-equivalent duplicate target {target}"
            )
        if certificate in certificates:
            raise ValueError(
                f"line {line_number}: duplicate certificate filename {certificate}"
            )
        targets.add(target)
        canonical_targets.add(canonical_target)
        certificates.add(certificate)
        records.append(Record(target, dimensions, exact_rank, certificate, digest))
    return records


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _set_positions(mask: int) -> tuple[int, ...]:
    positions: list[int] = []
    while mask:
        low_bit = mask & -mask
        positions.append(low_bit.bit_length() - 1)
        mask ^= low_bit
    return tuple(positions)


def _decode_pair(key: int, m: int, p: int) -> tuple[int, int, int, int]:
    a_coordinate, b_coordinate = divmod(key, m * p)
    i, j = divmod(a_coordinate, m)
    j_prime, k = divmod(b_coordinate, p)
    return i, j, j_prime, k


def _verify_one(arguments: tuple[Path, Record]) -> Result:
    root, record = arguments
    path = root / record.certificate
    if not path.is_file():
        raise ValueError(f"{record.target}: missing certificate {path}")

    actual_digest = _sha256(path)
    if actual_digest != record.sha256:
        raise ValueError(
            f"{record.target}: SHA-256 mismatch: manifest {record.sha256}, "
            f"actual {actual_digest}"
        )

    n, m, p = record.dimensions
    u_width = n * m
    v_width = m * p
    w_width = n * p
    pair_stride = v_width
    parity: dict[int, int] = {}
    support_cache: dict[int, tuple[int, ...]] = {}
    pair_xors = 0
    terms = 0

    with path.open() as stream:
        for line_number, line in enumerate(stream, start=1):
            fields = line.split()
            if len(fields) != 4 or fields[0] != "R":
                raise ValueError(
                    f"{record.target}: malformed term at certificate line {line_number}"
                )
            try:
                u, v, w = (int(field, 10) for field in fields[1:])
            except ValueError as error:
                raise ValueError(
                    f"{record.target}: non-decimal mask at line {line_number}"
                ) from error
            if u <= 0 or v <= 0 or w <= 0:
                raise ValueError(
                    f"{record.target}: zero or negative factor at line {line_number}"
                )
            if u.bit_length() > u_width:
                raise ValueError(
                    f"{record.target}: U mask exceeds {u_width} bits at line {line_number}"
                )
            if v.bit_length() > v_width:
                raise ValueError(
                    f"{record.target}: V mask exceeds {v_width} bits at line {line_number}"
                )
            if w.bit_length() > w_width:
                raise ValueError(
                    f"{record.target}: W mask exceeds {w_width} bits at line {line_number}"
                )

            u_support = support_cache.get(u)
            if u_support is None:
                u_support = _set_positions(u)
                support_cache[u] = u_support
            v_support = support_cache.get(v)
            if v_support is None:
                v_support = _set_positions(v)
                support_cache[v] = v_support
            pair_xors += len(u_support) * len(v_support)

            for a_coordinate in u_support:
                base = a_coordinate * pair_stride
                for b_coordinate in v_support:
                    key = base + b_coordinate
                    updated = parity.get(key, 0) ^ w
                    if updated:
                        parity[key] = updated
                    else:
                        parity.pop(key, None)
            terms += 1

    if terms != record.exact_rank:
        raise ValueError(
            f"{record.target}: certificate has {terms} terms, expected "
            f"{record.exact_rank}"
        )

    # T(A[i,j], B[j',k], C[i',k']) is one precisely when
    # j == j', i == i', and k == k'.  Grouping all C coordinates into the
    # W bitmask leaves n*m*p expected nonzero (A, B) entries.
    for i in range(n):
        for j in range(m):
            a_coordinate = i * m + j
            for k in range(p):
                b_coordinate = j * p + k
                key = a_coordinate * pair_stride + b_coordinate
                expected_w = 1 << (i * p + k)
                actual_w = parity.pop(key, 0)
                if actual_w != expected_w:
                    raise ValueError(
                        f"{record.target}: tensor mismatch at A[{i},{j}], "
                        f"B[{j},{k}]: expected W mask {expected_w}, got {actual_w}"
                    )

    if parity:
        key = next(iter(parity))
        i, j, j_prime, k = _decode_pair(key, m, p)
        raise ValueError(
            f"{record.target}: unexpected nonzero tensor coefficient at "
            f"A[{i},{j}], B[{j_prime},{k}] with W mask {parity[key]}"
        )

    return Result(
        record.target,
        record.exact_rank,
        record.certificate,
        actual_digest,
        terms,
        pair_xors,
        n * m * p,
    )


def _write_audit(path: Path, results: list[Result]) -> None:
    columns = (
        "target",
        "exact_rank",
        "certificate",
        "sha256",
        "terms",
        "pair_xors",
        "tensor_ones",
        "exact_gf2",
    )
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("w", newline="") as stream:
        writer = csv.writer(stream, delimiter="\t", lineterminator="\n")
        writer.writerow(columns)
        for result in results:
            writer.writerow(
                (
                    result.target,
                    result.exact_rank,
                    result.certificate,
                    result.sha256,
                    result.terms,
                    result.pair_xors,
                    result.tensor_ones,
                    1,
                )
            )
    temporary.replace(path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    default_root = Path(__file__).resolve().parent
    parser.add_argument(
        "--manifest",
        type=Path,
        default=default_root / "block_composition_records.tsv",
    )
    parser.add_argument(
        "--audit",
        type=Path,
        help="write a deterministic per-certificate TSV audit after all checks pass",
    )
    parser.add_argument(
        "-j",
        "--jobs",
        type=int,
        default=1,
        help="certificate processes (default: 1)",
    )
    args = parser.parse_args()
    if args.jobs < 1:
        parser.error("--jobs must be positive")

    started = time.perf_counter()
    manifest = args.manifest.resolve()
    records = _read_manifest(manifest)
    work = [(manifest.parent, record) for record in records]
    if args.jobs == 1:
        results = [_verify_one(item) for item in work]
    else:
        with ProcessPoolExecutor(max_workers=args.jobs) as executor:
            results = list(executor.map(_verify_one, work))

    if args.audit is not None:
        _write_audit(args.audit, results)

    elapsed = time.perf_counter() - started
    total_terms = sum(result.terms for result in results)
    total_pair_xors = sum(result.pair_xors for result in results)
    manifest_digest = _sha256(manifest)
    print(
        f"PASS exact GF(2) sparse-parity audit: certificates={len(results)} "
        f"terms={total_terms} pair_xors={total_pair_xors} "
        f"elapsed={elapsed:.3f}s"
    )
    print(f"manifest_sha256={manifest_digest}")
    if args.audit is not None:
        print(f"audit={args.audit} sha256={_sha256(args.audit)}")


if __name__ == "__main__":
    main()
