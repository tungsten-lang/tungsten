#!/usr/bin/env python3
"""Pinned LRC(13) SAT reference instances.

These are the three Goddyn--Wong terminal-lift encodings used to assess
Wassat's certificate lane.  They are generated rather than checked in as
roughly 0.8 MiB of opaque DIMACS: the specification below is short, exact,
and each materialized file is protected by its canonical SHA-256 digest.

All three instances are UNSAT.  They encode that the terminal lift of the
tight 13-speed Goddyn--Wong residue family has no improper completion at
level 14.  They are benchmarks and certificate-engine references, not a
claim to resolve LRC(13).
"""

from __future__ import annotations

import hashlib
import tempfile
from itertools import combinations
from math import gcd
from pathlib import Path


BASE = tuple(range(1, 12)) + (13, 24)
LEVEL = 14
INSTANCES = (
    (181, "f202d14eaff3a80dac79d22d653c8cbf8810514b30dcbd0665f0af8598050d2f"),
    (223, "30a5ad6cd08d52166a1e10de8e3fa8c647aa3834b5f4fc6a810df58088ab95ba"),
    (281, "d23289c0e05817fe0073381bcf9fc48240b656ad4d920e9bc2d577f4aaae9df0"),
)


def prime_divisors(n: int) -> tuple[int, ...]:
    out = []
    divisor = 2
    while divisor <= n // divisor:
        if n % divisor == 0:
            out.append(divisor)
            while n % divisor == 0:
                n //= divisor
        divisor += 1
    return tuple(out + ([n] if n > 1 else []))


def encode(prime: int) -> str:
    """Return the canonical terminal-lift CNF, including unit symmetry."""
    modulus = LEVEL * prime
    variables = {
        (coordinate, lift): 1 + coordinate * LEVEL + lift
        for coordinate in range(len(BASE))
        for lift in range(LEVEL)
    }
    clauses: list[list[int]] = []

    # Exactly one of the fourteen lifts in each coordinate fibre.
    for coordinate in range(len(BASE)):
        group = [variables[coordinate, lift] for lift in range(LEVEL)]
        clauses.append(group)
        for left in range(LEVEL):
            for right in range(left + 1, LEVEL):
                clauses.append([-variables[coordinate, left], -variables[coordinate, right]])

    # Unit multiplication modulo 14 preserves this p-fibre.  Select one
    # representative of each gcd orbit for the first coordinate, exactly as
    # in the certificate encoder.
    representatives = tuple(sorted({
        0 if gcd(value, LEVEL) == LEVEL else gcd(value, LEVEL)
        for value in range(LEVEL)
    }))
    clauses.append([
        variables[0, lift]
        for lift in range(LEVEL)
        if (BASE[0] + lift * prime) % LEVEL in representatives
    ])

    # Every sampled time must have at least one bad lift.  Times t and -t
    # generate the same condition, so retain one representative.
    for time in range(1, modulus // 2 + 1):
        clause = []
        for coordinate, residue in enumerate(BASE):
            for lift in range(LEVEL):
                speed = residue + lift * prime
                remainder = time * speed % modulus
                if LEVEL * remainder < modulus or LEVEL * (modulus - remainder) < modulus:
                    clause.append(variables[coordinate, lift])
        if not clause:
            raise AssertionError(f"sampled time {time} has no bad lift")
        clauses.append(clause)

    # Original drop-one gcd escape: a failed escape has at least two
    # nonmultiples of each prime divisor of 14.
    for divisor in prime_divisors(LEVEL):
        good = [
            variables[coordinate, lift]
            for coordinate, residue in enumerate(BASE)
            for lift in range(LEVEL)
            if (residue + lift * prime) % divisor
        ]
        clauses.append(good)
        for literal in good:
            clauses.append([-literal] + [other for other in good if other != literal])

    lines = [f"p cnf {len(BASE) * LEVEL} {len(clauses)}"]
    lines.extend(" ".join(map(str, clause)) + " 0" for clause in clauses)
    return "\n".join(lines) + "\n"


def materialize(root: Path | None = None) -> list[tuple[str, str]]:
    """Materialize and digest-check the three reference CNFs outside Git."""
    root = root or Path(tempfile.gettempdir()) / "wassat-lrc13-reference-v1"
    root.mkdir(parents=True, exist_ok=True)
    result = []
    for prime, expected_digest in INSTANCES:
        name = f"lr_k13_p{prime}_goddyn"
        path = root / f"{name}.cnf"
        data = encode(prime).encode()
        digest = hashlib.sha256(data).hexdigest()
        if digest != expected_digest:
            raise AssertionError(f"{name}: encoder drift {digest} != {expected_digest}")
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            path.write_bytes(data)
        result.append((name, str(path)))
    return result


if __name__ == "__main__":
    for name, path in materialize():
        print(f"{name}\t{path}")
