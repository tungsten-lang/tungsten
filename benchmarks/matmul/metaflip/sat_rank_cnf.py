"""Encode 'does <n,m,p> have a rank-R decomposition over GF(2)?' as DIMACS
CNF with native XOR clauses (CryptoMiniSat `x` lines).

Same Brent-equation encoding as sat_rank.py, but built for a solver with
Gaussian-elimination XOR handling: per entry triple (a,b,c) the constraint
    XOR_t AND(u[t][a], v[t][b], w[t][c]) = [diagonal]
gets one Tseitin variable per (t,a,b,c) conjunction (4 clauses each) and
one XOR line per triple. Plus no-zero-factor clauses per term.

Variable layout (1-based):
  u[t][a] = 1 + t*(AB+BB+CB) + a
  v[t][b] = u-block + AB + b
  w[t][c] = u-block + AB + BB + c
  AND vars follow all primaries, allocated in emission order.

Usage:  python3 sat_rank_cnf.py <n> <m> <p> <R> > inst.cnf
        cryptominisat5 inst.cnf            (10 = SAT, 20 = UNSAT)
Decode: python3 sat_rank_cnf.py <n> <m> <p> <R> --decode model.out
        (model.out = the solver's v-lines; emits us/vs/ws mask-seed block,
        exact-validated)
"""
import sys

from metaflip_proto2 import T, recon


def layout(n, m, p, R):
    AB, BB, CB = n * m, m * p, n * p
    stride = AB + BB + CB
    def u(t, a): return 1 + t * stride + a
    def v(t, b): return 1 + t * stride + AB + b
    def w(t, c): return 1 + t * stride + AB + BB + c
    return AB, BB, CB, stride, u, v, w


def emit(n, m, p, R, out):
    AB, BB, CB, stride, u, v, w = layout(n, m, p, R)
    nprimary = R * stride
    clauses = []
    xors = []
    nextvar = nprimary + 1
    for i in range(n):
        for j in range(m):
            a = i * m + j
            for j2 in range(m):
                for k in range(p):
                    b = j2 * p + k
                    for i2 in range(n):
                        for k2 in range(p):
                            c = i2 * p + k2
                            ands = []
                            for t in range(R):
                                g = nextvar
                                nextvar += 1
                                uu, vv, ww = u(t, a), v(t, b), w(t, c)
                                clauses.append((-g, uu))
                                clauses.append((-g, vv))
                                clauses.append((-g, ww))
                                clauses.append((g, -uu, -vv, -ww))
                                ands.append(g)
    # XOR lines in a second pass with identical AND-var allocation order
    xors = []
    nextvar2 = nprimary + 1
    for i in range(n):
        for j in range(m):
            for j2 in range(m):
                for k in range(p):
                    for i2 in range(n):
                        for k2 in range(p):
                            ands = list(range(nextvar2, nextvar2 + R))
                            nextvar2 += R
                            tgt = (j == j2 and i == i2 and k == k2)
                            if not tgt:
                                ands[0] = -ands[0]
                            xors.append(tuple(ands))
    # no all-zero factors
    for t in range(R):
        clauses.append(tuple(u(t, a) for a in range(AB)))
        clauses.append(tuple(v(t, b) for b in range(BB)))
        clauses.append(tuple(w(t, c) for c in range(CB)))
    out.write(f"p cnf {nextvar - 1} {len(clauses) + len(xors)}\n")
    for cl in clauses:
        out.write(" ".join(str(x) for x in cl) + " 0\n")
    for xl in xors:
        out.write("x" + " ".join(str(x) for x in xl) + " 0\n")


def decode(n, m, p, R, model_path):
    AB, BB, CB, stride, u, v, w = layout(n, m, p, R)
    tru = set()
    for line in open(model_path):
        if line.startswith("v"):
            for tok in line.split()[1:]:
                x = int(tok)
                if x > 0:
                    tru.add(x)
    S = set()
    for t in range(R):
        um = sum(1 << a for a in range(AB) if u(t, a) in tru)
        vm = sum(1 << b for b in range(BB) if v(t, b) in tru)
        wm = sum(1 << c for c in range(CB) if w(t, c) in tru)
        tt = (um, vm, wm)
        if um and vm and wm:
            S.discard(tt) if tt in S else S.add(tt)
    valid = recon(S, n, m, p) == T(n, m, p)
    print(f"decoded rank={len(S)} <{n},{m},{p}> exact-valid={valid}", file=sys.stderr)
    if not valid:
        sys.exit(1)
    terms = sorted(S)
    for k2, (a, b, c) in enumerate(terms):
        print(f"us[{k2}] = {a}")
    for k2, (a, b, c) in enumerate(terms):
        print(f"vs[{k2}] = {b}")
    for k2, (a, b, c) in enumerate(terms):
        print(f"ws[{k2}] = {c}")


if __name__ == "__main__":
    n, m, p, R = (int(x) for x in sys.argv[1:5])
    if len(sys.argv) > 5 and sys.argv[5] == "--decode":
        decode(n, m, p, R, sys.argv[6])
    else:
        emit(n, m, p, R, sys.stdout)
