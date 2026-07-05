"""SAT surgery: local re-decomposition of k scheme terms by k-1 terms.

For a GF(2) scheme and a k-subset K of its terms, form the partial tensor
P = XOR of K's rank-1 expansions, then ask a SAT solver whether k-1 masks
reproduce P exactly (Brent-style equations, RHS = P). A SAT answer replaces
K and drops the rank by one — no shared factors required, so this works
where the flip graph is isolated (every known rank-47 scheme).

Candidates are guided: subsets with the smallest joint support are the most
likely to re-decompose, so pairs are ranked by |P|, triples/quads extend the
best pairs. Each candidate gets a short z3 timeout; a scheme gets a total
budget.

Usage: python3 sat_surgery.py <schemefile> <n> <m> <p> [budget_s]
       python3 sat_surgery.py --selftest
Exit prints one line per candidate and a final verdict; a SAT hit writes
<schemefile>.reduced.txt and exact-validates it.
"""
import itertools
import re
import subprocess
import sys
import tempfile
import time

from metaflip_proto2 import T, recon


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


def expand(term, AB, BB, CB):
    """Rank-1 term -> python-int bitset over the (a,b,c) cube."""
    u, v, w = term
    bs = 0
    for a in range(AB):
        if not u >> a & 1:
            continue
        for b in range(BB):
            if not v >> b & 1:
                continue
            base = (a * BB + b) * CB
            for c in range(CB):
                if w >> c & 1:
                    bs |= 1 << (base + c)
    return bs


def smt_for(P, R, AB, BB, CB):
    out = ["(set-option :produce-models true)"]
    w = out.append
    for t in range(R):
        for a in range(AB):
            w(f"(declare-const u{t}_{a} Bool)")
        for b in range(BB):
            w(f"(declare-const v{t}_{b} Bool)")
        for c in range(CB):
            w(f"(declare-const w{t}_{c} Bool)")
    for a in range(AB):
        for b in range(BB):
            base = (a * BB + b) * CB
            for c in range(CB):
                terms = " ".join(f"(and u{t}_{a} v{t}_{b} w{t}_{c})" for t in range(R))
                tgt = "true" if P >> (base + c) & 1 else "false"
                w(f"(assert (= (xor {terms} false) {tgt}))")
    for t in range(R):
        w(f"(assert (or {' '.join(f'u{t}_{a}' for a in range(AB))}))")
        w(f"(assert (or {' '.join(f'v{t}_{b}' for b in range(BB))}))")
        w(f"(assert (or {' '.join(f'w{t}_{c}' for c in range(CB))}))")
    w("(check-sat)")
    w("(get-model)")
    return "\n".join(out)


def run_z3(smt, timeout_s):
    with tempfile.NamedTemporaryFile("w", suffix=".smt2", delete=False) as f:
        f.write(smt)
        path = f.name
    try:
        r = subprocess.run(["z3", f"-T:{timeout_s}", path],
                           capture_output=True, text=True, timeout=timeout_s + 5)
        return r.stdout
    except subprocess.TimeoutExpired:
        return "timeout"


def decode_model(out, R, AB, BB, CB):
    vals = {}
    for m in re.finditer(r"\(define-fun (\w+)_(\d+) \(\) Bool\s+(\w+)\)", out):
        vals[(m.group(1), int(m.group(2)))] = (m.group(3) == "true")
    new_terms = []
    for t in range(R):
        u = sum(1 << a for a in range(AB) if vals.get((f"u{t}", a)))
        v = sum(1 << b for b in range(BB) if vals.get((f"v{t}", b)))
        w = sum(1 << c for c in range(CB) if vals.get((f"w{t}", c)))
        new_terms.append((u, v, w))
    return new_terms


def surgery(path, n, m, p, budget_s=300, z3_timeout=20):
    AB, BB, CB = n * m, m * p, n * p
    terms = read_scheme(path)
    S = set()
    for t in terms:
        S.discard(t) if t in S else S.add(t)
    terms = sorted(S)
    assert recon(set(terms), n, m, p) == T(n, m, p), "input scheme invalid"
    R0 = len(terms)
    print(f"{path}: rank {R0}, budget {budget_s}s", flush=True)

    exp = [expand(t, AB, BB, CB) for t in terms]
    deadline = time.time() + budget_s

    # k=2 pairs ranked by joint support
    pairs = sorted(
        ((bin(exp[i] ^ exp[j]).count("1"), i, j)
         for i, j in itertools.combinations(range(R0), 2)),
        key=lambda x: x[0])
    cands = [(s, (i, j)) for s, i, j in pairs[:40]]
    # k=3: extend the best pairs by every third term, keep smallest supports
    triples = []
    for s, i, j in pairs[:60]:
        pij = exp[i] ^ exp[j]
        for l in range(R0):
            if l in (i, j):
                continue
            triples.append((bin(pij ^ exp[l]).count("1"), (i, j, l)))
    triples.sort(key=lambda x: x[0])
    cands += triples[:60]
    # k=4: extend the best triples
    quads = []
    for s, sub in triples[:20]:
        pt = exp[sub[0]] ^ exp[sub[1]] ^ exp[sub[2]]
        for l in range(R0):
            if l in sub:
                continue
            quads.append((bin(pt ^ exp[l]).count("1"), sub + (l,)))
    quads.sort(key=lambda x: x[0])
    cands += quads[:30]

    tried = 0
    for support, sub in cands:
        if time.time() > deadline:
            print(f"  budget exhausted after {tried} candidates", flush=True)
            break
        k = len(sub)
        P = 0
        for i in sub:
            P ^= exp[i]
        if P == 0:
            continue  # would already have cancelled
        out = run_z3(smt_for(P, k - 1, AB, BB, CB), z3_timeout)
        tried += 1
        verdict = "unsat" if "unsat" in out else ("sat" if out.startswith("sat") else "timeout")
        print(f"  k={k} support={support} -> {verdict}", flush=True)
        if verdict == "sat":
            new_terms = decode_model(out, k - 1, AB, BB, CB)
            check = 0
            for t in new_terms:
                check ^= expand(t, AB, BB, CB)
            if check != P:
                print("  MODEL DECODE MISMATCH — skipping", flush=True)
                continue
            reduced = [t for idx, t in enumerate(terms) if idx not in sub] + new_terms
            Sr = set()
            for t in reduced:
                Sr.discard(t) if t in Sr else Sr.add(t)
            ok = recon(Sr, n, m, p) == T(n, m, p)
            print(f"*** RANK REDUCED {R0} -> {len(Sr)} exact-valid={ok}", flush=True)
            if ok:
                outp = path + ".reduced.txt"
                with open(outp, "w") as f:
                    for u, v, w2 in sorted(Sr):
                        f.write(f"R {u} {v} {w2}\n")
                print(f"*** saved {outp}", flush=True)
                return True
    print(f"  no reduction ({tried} candidates tried)", flush=True)
    return False


def selftest():
    """Split one term of the naive 2x2 scheme into two; surgery must re-merge."""
    n = m = p = 2
    AB, BB, CB = 4, 4, 4
    naive = []
    for i in range(2):
        for j in range(2):
            for k in range(2):
                naive.append((1 << (i * 2 + j), 1 << (j * 2 + k), 1 << (i * 2 + k)))
    u, v, w = naive[0]
    split = [(u, v, w ^ 2), (u, v, 2)] + naive[1:]  # w = w1 ^ w2
    import os
    tmp = tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False)
    for t in split:
        tmp.write(f"R {t[0]} {t[1]} {t[2]}\n")
    tmp.close()
    ok = surgery(tmp.name, n, m, p, budget_s=60, z3_timeout=10)
    os.unlink(tmp.name)
    print("SELFTEST", "PASS" if ok else "FAIL", flush=True)
    return ok


if __name__ == "__main__":
    if sys.argv[1] == "--selftest":
        sys.exit(0 if selftest() else 1)
    path, n, m, p = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    budget = int(sys.argv[5]) if len(sys.argv) > 5 else 300
    surgery(path, n, m, p, budget_s=budget)
