#!/usr/bin/env python3
"""Generate the normalized rank-19 SAT shards for GF(2) <3,2,4>.

This does *not* prove the global lower bound.  It deterministically generates
the nine aggregate or 226 fully fixed-pair XNF instances whose collective
UNSAT would finish the remaining rank-19 exclusion after orbit 29 is raised.
By default the finite-group orbit table is re-enumerated before generation.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

from n324_common import (RANK_ONE_A, apply_a, gl_packed, inverse_square,
                         rank_square, row_times)


# Representatives independently re-enumerated by audit_residual_cases().
# Keys are (missing A pair, fixed A term), then normalized B, then allowed C.
EXPECTED_CASES = {
    ((1, 2), 3): {
        1: (1, 2, 8, 10, 11, 16, 20, 80, 84, 85, 160, 672),
        17: (1, 2, 8, 10, 11, 16, 20, 80, 84, 85, 160, 672),
        33: (1, 2, 9, 10, 11, 18, 20, 64, 66, 67, 82, 84, 85, 91,
             93, 128, 132, 164, 640, 644, 645, 676, 685, 1280),
    },
    ((1, 4), 5): {
        1: (1, 3, 4, 8, 10, 11, 12, 13, 24, 28, 31, 32, 80, 84, 85,
            87, 96, 224, 672),
        16: (1, 3, 4, 8, 10, 11, 12, 13, 24, 28, 31, 32, 80, 84, 85,
             87, 96, 224, 672),
        33: (1, 3, 4, 8, 10, 11, 12, 13, 24, 28, 31, 32, 64, 66, 67,
             68, 69, 80, 84, 85, 86, 87, 88, 92, 95, 96, 104, 192,
             196, 199, 224, 248, 256, 640, 644, 645, 647, 672, 680, 696,
             768, 1792),
    },
    ((1, 8), 15): {
        1: (1, 2, 3, 4, 8, 10, 11, 12, 13, 16, 17, 20, 22, 24, 28,
            31, 32, 80, 84, 85, 86, 87, 96, 160, 224, 672),
        17: (1, 3, 4, 8, 10, 11, 12, 13, 24, 28, 31, 32, 80, 84, 85,
             87, 96, 224, 672),
        33: (1, 2, 3, 4, 9, 10, 11, 12, 13, 17, 19, 20, 27, 28, 31,
             36, 64, 66, 67, 68, 69, 80, 82, 84, 85, 86, 87, 91, 92,
             94, 95, 96, 98, 100, 104, 106, 109, 192, 196, 199, 228,
             255, 256, 640, 644, 645, 646, 647, 676, 685, 703, 768,
             1792),
    },
}


def right_b(b: int, g: int) -> int:
    return row_times(b & 15, g, 4) | (row_times(b >> 4, g, 4) << 4)


def left_b(r: int, b: int) -> int:
    rows = (b & 15, b >> 4)
    out = 0
    for i in range(2):
        value = 0
        selector = (r >> (2 * i)) & 3
        for k in range(2):
            if (selector >> k) & 1:
                value ^= rows[k]
        out |= value << (4 * i)
    return out


def left_c(g: int, c: int) -> int:
    rows = [(c >> (3 * i)) & 7 for i in range(4)]
    out = 0
    for i in range(4):
        value = 0
        selector = (g >> (4 * i)) & 15
        for k in range(4):
            if (selector >> k) & 1:
                value ^= rows[k]
        out |= value << (3 * i)
    return out


def right_c(c: int, l: int) -> int:
    return sum(row_times((c >> (3 * i)) & 7, l, 3) << (3 * i)
               for i in range(4))


def enumerate_residual_cases() -> dict[
        tuple[tuple[int, int], int], dict[int, tuple[int, ...]]]:
    """Reconstruct all pair orbits under GL4 and the fixed-A stabilizer."""
    gl4 = [(g, inverse_square(g, 4)) for g in gl_packed(4)]
    to_normal: dict[int, tuple[int, int]] = {}
    for b in range(1, 256):
        row0, row1 = b & 15, b >> 4
        target = (33 if row0 and row1 and row0 != row1 else
                  1 if row0 and not row1 else
                  16 if row1 and not row0 else 17)
        _, inverse = next((g, inverse) for g, inverse in gl4
                          if right_b(b, g) == target)
        to_normal[b] = target, inverse

    ccanon: dict[int, list[int]] = {}
    for b in (1, 16, 17, 33):
        stabilizer_inverses = [inverse for g, inverse in gl4
                               if right_b(b, g) == b]
        canon = [0] * 4096
        for c in range(1, 4096):
            canon[c] = min(left_c(inverse, c)
                           for inverse in stabilizer_inverses)
        ccanon[b] = canon

    def canonical_pair(b: int, c: int) -> tuple[int, int]:
        target, inverse = to_normal[b]
        return target, ccanon[target][left_c(inverse, c)]

    nodes = sorted({canonical_pair(b, c) for b in range(1, 256)
                    for c in range(1, 4096)})
    assert len(nodes) == 353
    gl3, gl2 = gl_packed(3), gl_packed(2)
    result = {}
    expected_k_sizes = {(1, 2): 48, (1, 4): 16, (1, 8): 8}
    for missing, canonical_a in (((1, 2), 3), ((1, 4), 5), ((1, 8), 15)):
        kgroup = []
        for left in gl3:
            left_inverse = inverse_square(left, 3)
            for right in gl2:
                right_inverse = inverse_square(right, 2)
                if {apply_a(x, left, right) for x in missing} != set(missing):
                    continue
                if apply_a(canonical_a, left, right) != canonical_a:
                    continue
                kgroup.append((right_inverse, left_inverse))
        assert len(kgroup) == expected_k_sizes[missing]

        unseen = set(nodes)
        representatives = []
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
                    image = canonical_pair(left_b(right_inverse, b),
                                           right_c(c, left_inverse))
                    if image not in orbit:
                        stack.append(image)
            unseen.difference_update(orbit)
            representatives.append(min(orbit))
        by_b: dict[int, list[int]] = {}
        for b, c in representatives:
            by_b.setdefault(b, []).append(c)
        result[(missing, canonical_a)] = {
            b: tuple(cs) for b, cs in sorted(by_b.items())}
    return result


def audit_residual_cases() -> None:
    actual = enumerate_residual_cases()
    assert actual == EXPECTED_CASES
    assert [sum(map(len, actual[key].values())) for key in actual] == [48, 80, 98]
    print("residual_orbit_audit=PASS counts=48,80,98")


class Xnf:
    def __init__(self):
        self.nvars = 0
        self.clauses: list[list[int]] = []
        self.xors: list[tuple[list[int], int]] = []

    def var(self) -> int:
        self.nvars += 1
        return self.nvars

    def add(self, *lits: int) -> None:
        self.clauses.append(list(lits))

    def xor_eq(self, lits: list[int], rhs: int) -> None:
        assert lits
        self.xors.append((lits, rhs))

    def render(self, comments: list[str]) -> bytes:
        lines = [f"c {comment}" for comment in comments]
        lines.append(f"p cnf {self.nvars} {len(self.clauses) + len(self.xors)}")
        lines.extend(" ".join(map(str, clause)) + " 0"
                     for clause in self.clauses)
        for lits, rhs in self.xors:
            shown = lits if rhs else [-lits[0], *lits[1:]]
            lines.append("x " + " ".join(map(str, shown)) + " 0")
        return ("\n".join(lines) + "\n").encode()


def build_xnf(missing: tuple[int, int], canonical_a: int, fixed_b: int,
              allowed_c: tuple[int, ...], fixed_c: int | None) -> bytes:
    a = [x for x in RANK_ONE_A if x not in missing]
    assert len(a) == 19 and canonical_a in a
    term = a.index(canonical_a)
    xnf = Xnf()
    b = [[xnf.var() for _ in range(8)] for _ in range(19)]
    c = [[xnf.var() for _ in range(12)] for _ in range(19)]
    for t in range(19):
        xnf.add(*b[t])
        xnf.add(*c[t])
    for j, variable in enumerate(b[term]):
        xnf.add(variable if (fixed_b >> j) & 1 else -variable)
    if fixed_c is None:
        allowed = set(allowed_c)
        for mask in range(1 << 12):
            if mask in allowed:
                continue
            xnf.add(*[(-variable if (mask >> k) & 1 else variable)
                      for k, variable in enumerate(c[term])])
    else:
        assert fixed_c in allowed_c
        for k, variable in enumerate(c[term]):
            xnf.add(variable if (fixed_c >> k) & 1 else -variable)

    d = [[[xnf.var() for _ in range(12)] for _ in range(8)]
         for _ in range(19)]
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
                xnf.xor_eq([d[t][bj][ck] for t in range(19)
                            if (a[t] >> ai) & 1], rhs)
    return xnf.render([
        "GF(2) <3,2,4> normalized fixed-A rank-19 exact-decomposition shard",
        f"missing_rank1_A {missing[0]} {missing[1]}",
        f"A_factors {' '.join(map(str, a))}",
        f"canonical_term {term} A {canonical_a} fixed_B {fixed_b}",
        f"allowed_C_count {len(allowed_c)}",
        f"fixed_C {fixed_c if fixed_c is not None else 'aggregate'}",
        "AND Tseitin clauses plus 576 native XOR tensor equations",
    ])


def write_formula(path: Path, data: bytes,
                  manifest: list[tuple[str, str]]) -> None:
    path.write_bytes(data)
    manifest.append((hashlib.sha256(data).hexdigest(), path.name))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--mode", choices=("aggregate", "split", "all"),
                        default="all")
    parser.add_argument("--skip-audit", action="store_true")
    args = parser.parse_args()
    if not args.skip_audit:
        audit_residual_cases()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    manifest: list[tuple[str, str]] = []
    for (missing, canonical_a), by_b in EXPECTED_CASES.items():
        for fixed_b, allowed_c in by_b.items():
            stem = (f"n324_rank19_missing_{missing[0]}_{missing[1]}"
                    f"_a{canonical_a}_b{fixed_b}")
            if args.mode in ("aggregate", "all"):
                write_formula(args.output_dir / f"{stem}.xnf",
                              build_xnf(missing, canonical_a, fixed_b,
                                        allowed_c, None), manifest)
            if args.mode in ("split", "all"):
                for fixed_c in allowed_c:
                    write_formula(args.output_dir / f"{stem}_c{fixed_c}.xnf",
                                  build_xnf(missing, canonical_a, fixed_b,
                                            allowed_c, fixed_c), manifest)
    manifest.sort(key=lambda item: item[1])
    manifest_text = "".join(f"{digest}  {name}\n" for digest, name in manifest)
    (args.output_dir / "manifest.sha256").write_text(manifest_text)
    print(f"formulas={len(manifest)} manifest_sha256="
          f"{hashlib.sha256(manifest_text.encode()).hexdigest()}")


if __name__ == "__main__":
    main()
