#!/usr/bin/env python3
"""Convert a verified dense matmulcatalog scheme to FlipFleet's GF(2) text form.

matmulcatalog stores U and V in row-major order, but stores W in output-
transpose (column-major) order.  FlipFleet's certificate format uses row-major
coordinates for all three factors.  This importer reduces integral entries
modulo two, transposes W's flattening, and reconstructs the complete tensor
before writing the certificate.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Iterable


def _mask(values: Iterable[int]) -> int:
    result = 0
    for index, value in enumerate(values):
        if not isinstance(value, int):
            raise ValueError(f"non-integral coefficient at position {index}: {value!r}")
        if value & 1:
            result |= 1 << index
    return result


def _transpose_w(values: list[int], n: int, p: int) -> int:
    if len(values) != n * p:
        raise ValueError(f"W row has {len(values)} entries; expected {n * p}")
    result = 0
    for k in range(p):
        for i in range(n):
            value = values[k * n + i]
            if not isinstance(value, int):
                raise ValueError(f"non-integral W coefficient: {value!r}")
            if value & 1:
                result |= 1 << (i * p + k)
    return result


def _set_bits(mask: int):
    while mask:
        bit = mask & -mask
        yield bit.bit_length() - 1
        mask ^= bit


def _verify(n: int, m: int, p: int, terms: list[tuple[int, int, int]]) -> None:
    reconstructed: dict[tuple[int, int], int] = {}
    for u, v, w in terms:
        for a in _set_bits(u):
            for b in _set_bits(v):
                key = (a, b)
                reconstructed[key] = reconstructed.get(key, 0) ^ w

    for a in range(n * m):
        i, j = divmod(a, m)
        for b in range(m * p):
            j2, k = divmod(b, p)
            expected = 1 << (i * p + k) if j == j2 else 0
            if reconstructed.get((a, b), 0) != expected:
                raise ValueError(f"tensor mismatch at A[{i},{j}], B[{j2},{k}]")


def convert(source: Path, output: Path) -> tuple[tuple[int, int, int], int]:
    data = json.loads(source.read_text())
    if data.get("verified") is not True or "F2" not in data.get("fields", []):
        raise ValueError("source must be catalog-verified and explicitly valid over F2")

    dims = data.get("n")
    if not isinstance(dims, list) or len(dims) != 3:
        raise ValueError("missing three-dimensional catalog shape")
    n, m, p = dims
    rank = data.get("m")
    rows = (data.get("u"), data.get("v"), data.get("w"))
    if not isinstance(rank, int) or any(not isinstance(part, list) for part in rows):
        raise ValueError("dense u/v/w factors are required")
    u_rows, v_rows, w_rows = rows
    if len(u_rows) != rank or len(v_rows) != rank or len(w_rows) != rank:
        raise ValueError("factor row count does not match catalog rank")

    terms: list[tuple[int, int, int]] = []
    for term in range(rank):
        if len(u_rows[term]) != n * m or len(v_rows[term]) != m * p:
            raise ValueError(f"factor width mismatch in term {term}")
        terms.append(
            (_mask(u_rows[term]), _mask(v_rows[term]), _transpose_w(w_rows[term], n, p))
        )

    _verify(n, m, p, terms)
    output.write_text("".join(f"R {u} {v} {w}\n" for u, v, w in terms))
    return (n, m, p), rank


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    dims, rank = convert(args.source, args.output)
    print(f"PASS {'x'.join(map(str, dims))} rank {rank}: {args.output}")


if __name__ == "__main__":
    main()
