#!/usr/bin/env python3
"""Export a FlipFleet certificate as a dense, independently verified GF(2) JSON scheme.

FlipFleet stores all three factors as row-major bit masks.  The public FMM JSON
convention stores U as n1*n2, V as n2*n3, and W as n3*n1 (output-transpose)
rows.  This tool performs that W permutation, reconstructs every tensor
coefficient before writing, reparses the JSON, and reconstructs it again.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def _set_bits(mask: int):
    while mask:
        bit = mask & -mask
        yield bit.bit_length() - 1
        mask ^= bit


def _parse(path: Path, widths: tuple[int, int, int]) -> list[tuple[int, int, int]]:
    lines = [(number, raw) for number, raw in enumerate(path.read_text().splitlines(), 1) if raw.strip()]
    if not lines:
        raise ValueError("empty certificate")
    legacy_rank: int | None = None
    if len(lines[0][1].split()) == 1:
        legacy_rank = int(lines[0][1])
        lines = lines[1:]
    terms: list[tuple[int, int, int]] = []
    for line_number, raw in lines:
        fields = raw.split()
        if legacy_rank is not None:
            if len(fields) != 3:
                raise ValueError(f"{path}:{line_number}: expected 'U V W'")
            values = fields
        else:
            if len(fields) != 4 or fields[0] != "R":
                raise ValueError(f"{path}:{line_number}: expected 'R U V W'")
            values = fields[1:]
        if len(values) != 3:
            raise ValueError(f"{path}:{line_number}: expected 'R U V W'")
        term = tuple(int(value) for value in values)
        if any(value <= 0 for value in term):
            raise ValueError(f"{path}:{line_number}: factors must be nonzero")
        if any(value.bit_length() > width for value, width in zip(term, widths)):
            raise ValueError(f"{path}:{line_number}: factor exceeds declared shape")
        terms.append(term)  # type: ignore[arg-type]
    if legacy_rank is not None and len(terms) != legacy_rank:
        raise ValueError(f"declared rank {legacy_rank} but read {len(terms)} terms")
    if len(set(terms)) != len(terms):
        raise ValueError("duplicate rank-one terms are not canonical over GF(2)")
    return terms


def _verify(n1: int, n2: int, n3: int, terms: list[tuple[int, int, int]]) -> None:
    reconstructed: dict[tuple[int, int], int] = {}
    for u, v, w in terms:
        for a in _set_bits(u):
            for b in _set_bits(v):
                reconstructed[(a, b)] = reconstructed.get((a, b), 0) ^ w
    for a in range(n1 * n2):
        i, j = divmod(a, n2)
        for b in range(n2 * n3):
            j2, k = divmod(b, n3)
            expected = 1 << (i * n3 + k) if j == j2 else 0
            actual = reconstructed.get((a, b), 0)
            if actual != expected:
                raise ValueError(
                    f"tensor mismatch at A[{i},{j}], B[{j2},{k}]: "
                    f"actual={actual} expected={expected}"
                )


def _dense(mask: int, width: int) -> list[int]:
    return [(mask >> bit) & 1 for bit in range(width)]


def _dense_w(mask: int, n1: int, n3: int) -> list[int]:
    # FlipFleet bit (i,k) becomes public output-transpose position (k,i).
    return [(mask >> (i * n3 + k)) & 1 for k in range(n3) for i in range(n1)]


def _mask(values: list[int]) -> int:
    out = 0
    for bit, value in enumerate(values):
        if value not in (0, 1):
            raise ValueError(f"non-binary coefficient at position {bit}: {value!r}")
        out |= value << bit
    return out


def _mask_w(values: list[int], n1: int, n3: int) -> int:
    if len(values) != n1 * n3:
        raise ValueError("wrong dense W width")
    out = 0
    for k in range(n3):
        for i in range(n1):
            out |= values[k * n1 + i] << (i * n3 + k)
    return out


def export(source: Path, output: Path, n1: int, n2: int, n3: int) -> int:
    widths = (n1 * n2, n2 * n3, n1 * n3)
    terms = _parse(source, widths)
    _verify(n1, n2, n3, terms)
    data = {
        "n": [n1, n2, n3],
        "m": len(terms),
        "z2": True,
        "u": [_dense(u, widths[0]) for u, _, _ in terms],
        "v": [_dense(v, widths[1]) for _, v, _ in terms],
        "w": [_dense_w(w, n1, n3) for _, _, w in terms],
        "type": "tensor",
    }
    output.write_text(json.dumps(data, indent=2, separators=(",", ": ")) + "\n")

    # Treat the serialized representation as untrusted and repeat the full
    # reconstruction after applying the inverse W permutation.
    decoded = json.loads(output.read_text())
    if decoded.get("n") != [n1, n2, n3] or decoded.get("m") != len(terms):
        raise ValueError("serialized shape/rank mismatch")
    if decoded.get("z2") is not True:
        raise ValueError("serialized field marker is not GF(2)")
    roundtrip = [
        (_mask(u), _mask(v), _mask_w(w, n1, n3))
        for u, v, w in zip(decoded["u"], decoded["v"], decoded["w"])
    ]
    if roundtrip != terms:
        raise ValueError("serialized factors do not round-trip")
    _verify(n1, n2, n3, roundtrip)
    return len(terms)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("n1", type=int)
    parser.add_argument("n2", type=int)
    parser.add_argument("n3", type=int)
    args = parser.parse_args()
    if min(args.n1, args.n2, args.n3) < 1:
        parser.error("dimensions must be positive")
    rank = export(args.source, args.output, args.n1, args.n2, args.n3)
    print(f"PASS {args.n1}x{args.n2}x{args.n3} rank {rank}: {args.output}")


if __name__ == "__main__":
    main()
