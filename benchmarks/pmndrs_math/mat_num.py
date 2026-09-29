#!/usr/bin/env python3
"""Numeric comparison for mat_ab.w: every candidate vs its control and vs the
exact result.

usage: mat_num.py <mat_ab binary> <inputs per kind>

The binary's dump modes print `D <kind> <n> <tag> <values...>` at 17
significant digits (round-trip exact). Input kinds: 0 well-conditioned,
1 near-singular (cond ~1e8), 2 affine; compose: non-unit and unit q. Exact references are computed with
Fractions (Decimal at 60 digits for compose, which needs a sqrt).

Columns:
  same%    elements bit-identical to the control
  ulp/ctl  max elementwise ulp distance to the control
  ulp/ex   max elementwise ulp error vs the correctly rounded exact value
  nrm/ex   max normwise error |x - exact|_max / |exact|_max, in units of
           2^-52 (the control's own figure is on the control row)
Elementwise ulp columns skip entries smaller than 1e-8 x the output's
largest entry (pure cancellation noise, meaningless in ulps).
"""
import struct
import subprocess
import sys
from collections import defaultdict
from decimal import Decimal, getcontext
from fractions import Fraction

EPS = 2.0 ** -52
KINDS = {0: "well", 1: "near-sing", 2: "affine"}
COMPOSE_KINDS = {0: "q-nonunit", 1: "q-unit"}
GROUPS = [
    # dump, group, control, candidates, exact-fn name, kinds
    ("dump4", "inv4", "copy", ["core", "base", "recip", "nn", "fast", "into_inplace", "into_nn_inplace"], "inv", (0, 1, 2)),
    ("dump4", "inv4", "copy", ["affine"], "inv", (2,)),
    ("dump4", "mul4", "copy", ["core", "base", "fast", "into_copy", "into_fast", "into_alias_a", "into_alias_b"], "mul", (0, 1, 2)),
    ("dump4", "mv4", "copy", ["core", "fast", "into"], "mv", (0, 1, 2)),
    ("dump4", "tp", "user", ["plain", "fast"], "tp", (0, 1, 2)),
    ("dump4", "td", "user", ["fast"], "td", (0, 1, 2)),
    ("dump4", "tr4", "copy", ["into_inplace"], "tr", (0, 1, 2)),
    ("dump3", "inv3", "copy", ["core", "base", "recip", "nn", "fast", "into_inplace", "into_nn_inplace"], "inv", (0, 1, 2)),
    ("dump3", "mul3", "copy", ["core", "fast", "into_copy", "into_alias_a", "into_alias_b"], "mul", (0, 1, 2)),
    ("dump3", "det3", "copy", ["core", "fast"], "det", (0, 1, 2)),
    ("dump3", "mv3", "copy", ["core", "fast", "into"], "mv", (0, 1, 2)),
    ("dump2", "inv2", "copy", ["core", "base", "recip", "nn", "fast"], "inv", (0, 1, 2)),
    ("dumpc", "compose", "user", ["fast", "fast_metal"], "compose", (0, 1)),
]


def ordered(x):
    b = struct.unpack("<q", struct.pack("<d", x))[0]
    return b if b >= 0 else -(b & 0x7FFFFFFFFFFFFFFF)


def ulp(a, b):
    return abs(ordered(a) - ordered(b))


def mat(e):
    n = int(round(len(e) ** 0.5))
    return [[Fraction(e[c * n + r]) for c in range(n)] for r in range(n)], n


def flat(m, n):
    return [m[r][c] for c in range(n) for r in range(n)]


def inv_exact(e):
    a, n = mat(e)
    aug = [row[:] + [Fraction(int(i == r)) for i in range(n)] for r, row in enumerate(a)]
    for c in range(n):
        p = next(r for r in range(c, n) if aug[r][c] != 0)
        aug[c], aug[p] = aug[p], aug[c]
        pv = aug[c][c]
        aug[c] = [x / pv for x in aug[c]]
        for r in range(n):
            if r != c and aug[r][c] != 0:
                f = aug[r][c]
                aug[r] = [x - f * y for x, y in zip(aug[r], aug[c])]
    return flat([row[n:] for row in aug], n)


def det_exact(e):
    a, n = mat(e)
    return [a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
            - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
            + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])]


def exact(kind_fn, d):
    e = d.get("in")
    if kind_fn == "inv":
        return inv_exact(e)
    if kind_fn == "det":
        return det_exact(e)
    if kind_fn == "tr":
        a, n = mat(e)
        return [a[c][r] for c in range(n) for r in range(n)]
    if kind_fn == "mul":
        a, n = mat(e)
        b, _ = mat(d["in2"])
        return flat([[sum(a[r][k] * b[k][c] for k in range(n)) for c in range(n)] for r in range(n)], n)
    if kind_fn == "mv":
        a, n = mat(e)
        v = [Fraction(x) for x in d["vin"]]
        return [sum(a[r][k] * v[k] for k in range(n)) for r in range(n)]
    if kind_fn in ("tp", "td"):
        a, n = mat(e)
        p = [Fraction(x) for x in d["pin"]] + [Fraction(1 if kind_fn == "tp" else 0)]
        o = [sum(a[r][k] * p[k] for k in range(4)) for r in range(4)]
        return [o[r] / o[3] for r in range(3)] if kind_fn == "tp" else o[:3]
    if kind_fn == "compose":
        getcontext().prec = 60
        w, x, y, z = (Decimal(repr(v)) for v in d["qin"])
        t = [Decimal(repr(v)) for v in d["tin"]]
        s = [Decimal(repr(v)) for v in d["sin"]]
        nrm = (w * w + x * x + y * y + z * z).sqrt()
        w, x, y, z = w / nrm, x / nrm, y / nrm, z / nrm
        one, two = Decimal(1), Decimal(2)
        r = [one - two * (y * y + z * z), two * (x * y + w * z), two * (x * z - w * y),
             two * (x * y - w * z), one - two * (x * x + z * z), two * (y * z + w * x),
             two * (x * z + w * y), two * (y * z - w * x), one - two * (x * x + y * y)]
        out = []
        for c in range(3):
            out += [r[c * 3 + i] * s[c] for i in range(3)] + [Decimal(0)]
        out += t + [one]
        return [Fraction(v) for v in out]
    raise ValueError(kind_fn)


def run(binary, mode, n):
    p = subprocess.run([binary, mode, str(n)], capture_output=True, text=True)
    if p.returncode != 0:
        sys.exit(f"{mode} failed:\n{p.stdout[-2000:]}\n{p.stderr[-2000:]}")
    data = defaultdict(dict)
    for line in p.stdout.splitlines():
        if not line.startswith("D "):
            continue
        parts = line.split()
        data[(int(parts[1]), int(parts[2]))][parts[3]] = [float(v) for v in parts[4:]]
    return data


def stats(vals, ref, ex):
    """ref: control floats; ex: exact Fractions."""
    exf = [float(v) for v in ex]
    scale = max(abs(v) for v in exf) or 1.0
    keep = [i for i, v in enumerate(exf) if abs(v) >= 1e-8 * scale]
    same = sum(1 for a, b in zip(vals, ref) if struct.pack("<d", a) == struct.pack("<d", b))
    return {
        "same": same, "n": len(vals),
        "ulp_ctl": max((ulp(vals[i], ref[i]) for i in keep), default=0),
        "ulp_ex": max((ulp(vals[i], exf[i]) for i in keep), default=0),
        "nrm_ex": max(float(abs(Fraction(v) - e)) for v, e in zip(vals, ex)) / scale / EPS,
    }


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    binary, n = sys.argv[1], int(sys.argv[2])
    dumps = {m: run(binary, m, n) for m in sorted({g[0] for g in GROUPS})}
    print(f"{'group':<9}{'kind':<11}{'impl':<14}{'same%':>7}{'ulp/ctl':>9}{'ulp/ex':>9}{'nrm/ex':>12}")
    for mode, group, ctl, cands, fn, kinds in GROUPS:
        for kind in kinds:
            acc = defaultdict(lambda: {"same": 0, "n": 0, "ulp_ctl": 0, "ulp_ex": 0, "nrm_ex": 0.0})
            for (k, _), d in dumps[mode].items():
                if k != kind:
                    continue
                ex = exact(fn, d)
                ref = d[f"{group}.{ctl}"]
                for impl in [ctl] + cands:
                    s = stats(d[f"{group}.{impl}"], ref, ex)
                    a = acc[impl]
                    a["same"] += s["same"]
                    a["n"] += s["n"]
                    for key in ("ulp_ctl", "ulp_ex", "nrm_ex"):
                        a[key] = max(a[key], s[key])
            for impl in [ctl] + cands:
                a = acc[impl]
                tag = impl + ("*" if impl == ctl else "")
                label = (COMPOSE_KINDS if group == "compose" else KINDS)[kind]
                print(f"{group:<9}{label:<11}{tag:<14}{100.0 * a['same'] / a['n']:>7.1f}"
                      f"{a['ulp_ctl']:>9}{a['ulp_ex']:>9}{a['nrm_ex']:>12.3g}")


if __name__ == "__main__":
    main()
