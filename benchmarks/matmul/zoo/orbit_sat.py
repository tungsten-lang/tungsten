"""Orbit-encoded SAT: does a C3-symmetric rank-R scheme for <n,n,n> exist
over GF(2)?

The C3 action sig(u,v,w) = (v, tr w, tr u) (order 3; tr = transpose) lets a
symmetric scheme be described by t free orbits + f fixed terms, R = 3t + f.
Fixed terms have the shape (x, x, tr x). Encoding variables are one
representative (u,v,w) per orbit (3*n^2 bools) plus one x per fixed term
(n^2 bools) — about 3x fewer than the raw Brent system, which is the regime
where SAT has historically had a chance.

Modes:
  --validate <schemefile> <n>   partition a known symmetric scheme into
                                orbits, pin every variable, expect sat
                                (proves the equations are encoded right)
  --find <n> <t> <f> [timeout_s]  free search / refutation

An unsat from --find rules out C3-symmetric rank-(3t+f) schemes of that
shape — a citable partial lower-bound statement.
"""
import re
import subprocess
import sys
import tempfile


def trperm(n):
    return [(b % n) * n + (b // n) for b in range(n * n)]


def read_scheme(path):
    terms = []
    us, vs, ws = {}, {}, {}
    for ln in open(path):
        ln = ln.strip()
        if ln.startswith("R "):
            terms.append(tuple(int(x) for x in ln.split()[1:]))
        elif ln.startswith(("us[", "vs[", "ws[")):
            m = re.match(r"(us|vs|ws)\[(\d+)\] = (\d+)", ln)
            {"us": us, "vs": vs, "ws": ws}[m.group(1)][int(m.group(2))] = int(m.group(3))
        elif len(ln.split()) == 3:
            terms.append(tuple(int(x) for x in ln.split()))
    if us:
        terms = [(us[i], vs[i], ws[i]) for i in sorted(us)]
    return terms


def tr_mask(mask, n):
    p = trperm(n)
    r = 0
    for b in range(n * n):
        if mask >> b & 1:
            r |= 1 << p[b]
    return r


def sig(term, n):
    u, v, w = term
    return (v, tr_mask(w, n), tr_mask(u, n))


def orbits_of(terms, n):
    left = set(terms)
    orbs, fixed = [], []
    while left:
        t = next(iter(left))
        o = {t, sig(t, n), sig(sig(t, n), n)}
        if len(o) == 1:
            fixed.append(t)
        else:
            assert len(o) == 3, "order-2 point impossible for this action"
            assert o <= left, "term set not sig-closed"
            orbs.append(t)
        left -= o
    return orbs, fixed


def emit(n, t_orbits, f_fixed, pins=None):
    """SMT2 for t orbits + f fixed terms summing to T(n,n,n).
    pins: optional list of concrete (u,v,w) orbit reps + fixed x masks."""
    D = n * n
    P = trperm(n)
    out = ["(set-option :produce-models true)"]
    w = out.append
    for i in range(t_orbits):
        for nm in ("u", "v", "w"):
            for b in range(D):
                w(f"(declare-const {nm}{i}_{b} Bool)")
    for i in range(f_fixed):
        for b in range(D):
            w(f"(declare-const x{i}_{b} Bool)")

    def lit(name, i, b, tr=False):
        return f"{name}{i}_{P[b] if tr else b}"

    for a in range(D):
        for b in range(D):
            for c in range(D):
                parts = []
                for i in range(t_orbits):
                    # (u,v,w), (v, tr w, tr u), (tr w, u, tr v)
                    parts.append(f"(and {lit('u',i,a)} {lit('v',i,b)} {lit('w',i,c)})")
                    parts.append(f"(and {lit('v',i,a)} {lit('w',i,b,True)} {lit('u',i,c,True)})")
                    parts.append(f"(and {lit('w',i,a,True)} {lit('u',i,b)} {lit('v',i,c,True)})")
                for i in range(f_fixed):
                    parts.append(f"(and {lit('x',i,a)} {lit('x',i,b)} {lit('x',i,c,True)})")
                i_, j_ = divmod(a, n)
                j2, k_ = divmod(b, n)
                i2, k2 = divmod(c, n)
                tgt = "true" if (j_ == j2 and i_ == i2 and k_ == k2) else "false"
                w(f"(assert (= (xor {' '.join(parts)} false) {tgt}))")
    # no zero factors
    for i in range(t_orbits):
        for nm in ("u", "v", "w"):
            w(f"(assert (or {' '.join(f'{nm}{i}_{b}' for b in range(D))}))")
    for i in range(f_fixed):
        w(f"(assert (or {' '.join(f'x{i}_{b}' for b in range(D))}))")
    # optional pinning (validation mode)
    if pins is not None:
        orbs, fixed = pins
        assert len(orbs) == t_orbits and len(fixed) == f_fixed
        for i, (u, v, ww) in enumerate(orbs):
            for b in range(D):
                w(f"(assert (= u{i}_{b} {'true' if u >> b & 1 else 'false'}))")
                w(f"(assert (= v{i}_{b} {'true' if v >> b & 1 else 'false'}))")
                w(f"(assert (= w{i}_{b} {'true' if ww >> b & 1 else 'false'}))")
        for i, (x, _, _) in enumerate(fixed):
            for b in range(D):
                w(f"(assert (= x{i}_{b} {'true' if x >> b & 1 else 'false'}))")
    # light symmetry breaking on orbit order (free mode only)
    if pins is None and t_orbits > 1:
        for i in range(t_orbits - 1):
            conds, prefix = [], []
            for b in range(D):
                ltb = f"(and (not u{i}_{b}) u{i+1}_{b})"
                conds.append(f"(and {' '.join(prefix)} {ltb})" if prefix else ltb)
                prefix.append(f"(= u{i}_{b} u{i+1}_{b})")
            w(f"(assert (or {' '.join(conds)} (and {' '.join(prefix)})))")
    w("(check-sat)")
    w("(get-model)")
    return "\n".join(out)


def run_z3(smt, timeout_s):
    with tempfile.NamedTemporaryFile("w", suffix=".smt2", delete=False) as f:
        f.write(smt)
        path = f.name
    print(f"smt2 at {path} ({len(smt)//1024}KB), z3 -T:{timeout_s} ...", flush=True)
    r = subprocess.run(["z3", f"-T:{timeout_s}", path], capture_output=True, text=True,
                       timeout=timeout_s + 30)
    return r.stdout


def main():
    if sys.argv[1] == "--validate":
        path, n = sys.argv[2], int(sys.argv[3])
        terms = read_scheme(path)
        S = set()
        for t in terms:
            S.discard(t) if t in S else S.add(t)
        orbs, fixed = orbits_of(sorted(S), n)
        print(f"{path}: rank {len(S)} = 3*{len(orbs)} + {len(fixed)} fixed")
        fixed_full = [(x, x, tr_mask(x, n)) if not isinstance(x, tuple) else x for x in fixed]
        out = run_z3(emit(n, len(orbs), len(fixed), pins=(orbs, fixed_full)), 120)
        print("VALIDATE:", out.splitlines()[0] if out else "no output")
    elif sys.argv[1] == "--find":
        n, t, f = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
        timeout = int(sys.argv[5]) if len(sys.argv) > 5 else 3600
        print(f"searching C3-symmetric rank-{3*t+f} = 3*{t}+{f} at n={n}, timeout {timeout}s")
        out = run_z3(emit(n, t, f), timeout)
        first = out.splitlines()[0] if out else "no output"
        print("RESULT:", first, flush=True)
        if first == "sat":
            print(out[:20000])
            print("*** SAT — decode the model immediately; this is a symmetric record-rank scheme ***")


if __name__ == "__main__":
    main()
