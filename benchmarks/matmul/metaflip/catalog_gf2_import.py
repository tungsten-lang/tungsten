#!/usr/bin/env python3
"""Convert a verified dense/sparse matmulcatalog scheme to GF(2) text form.

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
        if type(value) is not int:
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
            if type(value) is not int:
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


def _factor_rows(data: dict, name: str, rank: int, width: int) -> list[list[int]]:
    """Decode canonical sparse indices; never trust a claimed verified flag."""
    dense = data.get(name)
    sparse = data.get(name + "_sparse")
    if dense is None and sparse is None:
        raise ValueError(f"missing {name} factor")
    if dense is not None:
        if not isinstance(dense, list) or len(dense) != rank:
            raise ValueError(f"{name} factor row count does not match rank")
        for row in dense:
            if not isinstance(row, list) or len(row) != width or any(type(c) is not int for c in row):
                raise ValueError(f"{name} requires integral rows of width {width}")
    if sparse is not None:
        if not isinstance(sparse, dict) or set(sparse) != {str(i) for i in range(rank)}:
            raise ValueError(f"{name} sparse row keys must cover the rank exactly")
        decoded = []
        for index in range(rank):
            entry = sparse[str(index)]
            if not isinstance(entry, dict) or set(entry) != {"i", "c"}:
                raise ValueError(f"invalid {name} sparse row {index}")
            indices, coefficients = entry["i"], entry["c"]
            if not isinstance(indices, list) or not isinstance(coefficients, list) or len(indices) != len(coefficients):
                raise ValueError(f"{name} sparse index/coefficient lengths differ")
            if any(type(i) is not int or not 0 <= i < width for i in indices):
                raise ValueError(f"{name} sparse index outside factor width")
            if len(set(indices)) != len(indices) or any(type(c) is not int for c in coefficients):
                raise ValueError(f"{name} sparse indices must be unique and coefficients integral")
            row = [0] * width
            for i, c in zip(indices, coefficients):
                row[i] = c
            decoded.append(row)
        if dense is not None and dense != decoded:
            raise ValueError(f"conflicting dense/sparse {name} encodings")
        dense = decoded
    return dense


def _linear_mask(row, basis: list[int], name: str) -> int:
    """Evaluate a linear form exactly in F2; no forward/cyclic references."""
    if not isinstance(row, list):
        raise ValueError(f"{name} circuit row must be a list")
    result = 0
    for entry in row:
        if not isinstance(entry, dict) or set(entry) != {"index", "value"}:
            raise ValueError(f"invalid {name} circuit entry")
        index, value = entry["index"], entry["value"]
        if type(index) is not int or not 0 <= index < len(basis):
            raise ValueError(f"{name} circuit index is out of range or a forward reference")
        if type(value) is not int:
            raise ValueError(f"{name} circuit coefficient must be integral")
        if value & 1:
            result ^= basis[index]
    return result


def _circuit_masks(data: dict, name: str, rows: int, width: int) -> list[int]:
    fresh = data.get(name + "_fresh", [])
    if not isinstance(fresh, list):
        raise ValueError(f"{name} fresh intermediates must be a list")
    basis = [1 << i for i in range(width)]
    for row in fresh:
        basis.append(_linear_mask(row, basis, name))
    forms = data.get(name)
    if not isinstance(forms, list) or len(forms) != rows:
        raise ValueError(f"{name} circuit requires {rows} rows")
    return [_linear_mask(row, basis, name) for row in forms]


def _circuit_rows(data: dict, rank: int, n: int, m: int, p: int):
    # Perminov reduced format: U/V intermediates combine input coordinates;
    # W intermediates combine products. W has output rows in column-major
    # order, unlike the rank-row dense and canonical sparse encodings.
    # Layout reference: pinned matmulcatalog SchemeIO.readReducedFromNode.
    if any(name + "_sparse" in data for name in ("u", "v", "w")):
        raise ValueError("mixed circuit/sparse encodings are not supported")
    u = _circuit_masks(data, "u", rank, n * m)
    v = _circuit_masks(data, "v", rank, m * p)
    outputs = _circuit_masks(data, "w", n * p, rank)
    return ([[mask >> i & 1 for i in range(n * m)] for mask in u],
            [[mask >> i & 1 for i in range(m * p)] for mask in v],
            [[mask >> term & 1 for mask in outputs] for term in range(rank)])


def _has_circuit_encoding(data: dict) -> bool:
    # Some catalog conversions retain unused *_fresh annotations after
    # expanding all three factors to canonical sparse input-coordinate rows.
    # Those complete rows are self-contained: bounds and the full tensor are
    # still checked below. Do not apply this exception to mixed/live circuits.
    if all(name + "_sparse" in data and name not in data for name in ("u", "v", "w")):
        return False
    return any(name + "_fresh" in data or
               (isinstance(data.get(name), list) and
                any(isinstance(row, list) and any(isinstance(entry, dict) for entry in row)
                    for row in data[name])) for name in ("u", "v", "w"))


def convert(source: Path, output: Path) -> tuple[tuple[int, int, int], int]:
    data = json.loads(source.read_text())
    if (data.get("verified") is not True or "F2" not in data.get("fields", []) or
            "F2" in data.get("fields_not", []) or data.get("commutative") or
            data.get("scheme_type") == "non_bilinear"):
        raise ValueError("source must be catalog-verified, bilinear, and explicitly valid over F2")

    dims = data.get("n")
    if not isinstance(dims, list) or len(dims) != 3 or any(type(d) is not int or d <= 0 for d in dims):
        raise ValueError("missing positive three-dimensional catalog shape")
    n, m, p = dims
    rank = data.get("m")
    if type(rank) is not int or rank <= 0:
        raise ValueError("positive integral catalog rank is required")
    if _has_circuit_encoding(data):
        u_rows, v_rows, w_rows = _circuit_rows(data, rank, n, m, p)
    else:
        u_rows = _factor_rows(data, "u", rank, n * m)
        v_rows = _factor_rows(data, "v", rank, m * p)
        w_rows = _factor_rows(data, "w", rank, n * p)

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
