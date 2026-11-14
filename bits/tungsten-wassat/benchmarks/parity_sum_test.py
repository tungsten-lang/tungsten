#!/usr/bin/env python3
"""Exhaustive-model test for the parity-sum lane (lib/parity_sum.w).

    WASSAT=<binary> [CASES=600] [SEED=1] python3 parity_sum_test.py

Generates formulas of at most 18 variables from parity constraints on the
vertices of small random multigraphs (Tseitin formulas, with a random or an
odd total charge), exact-cardinality constraints in the binomial encoding,
flipped literals, units and equivalences, dangling variables, clauses removed
from a constraint (so that it is no longer one), and unrelated clauses. The
verdict of every case is checked against enumeration of all assignments, so a
refutation the lane reports for a satisfiable formula fails the test; a
reported model must satisfy the input.

A run in which the lane rarely answers proves nothing, so the test also fails
when the lane decided fewer than a sixth of the formulas (it answers about
23% of them; only refutations by parity are its to give).
"""
import os, random, subprocess, sys, tempfile, itertools
W = os.environ.get('WASSAT') or sys.exit('set WASSAT=<binary>')
N = int(os.environ.get('CASES', '600')); SEED = int(os.environ.get('SEED', '1'))
TMP = tempfile.mkdtemp(prefix='parity-sum-')
rng = random.Random(SEED)
env = dict(os.environ, WASSAT_BACKDOOR_TABLES='0')

def xor_clauses(vs, rhs):
    """sum(vs) = rhs (mod 2): forbid every assignment of the other parity."""
    out = []
    for bits in itertools.product((0, 1), repeat=len(vs)):
        if sum(bits) % 2 != rhs:
            out.append([-v if b else v for v, b in zip(vs, bits)])     # false exactly under `bits`
    return out

def exactly(lits, a):
    n = len(lits)
    lo = [list(c) for c in itertools.combinations(lits, n - a + 1)]
    hi = [[-l for l in c] for c in itertools.combinations(lits, a + 1)]
    return lo + hi

def gen():
    cl = []; nv = 0
    kind = rng.random()
    if kind < 0.6:                                   # Tseitin on a random multigraph, degree <= 5
        nvert = rng.randint(3, 8); deg = [0] * nvert; edges = []
        for _ in range(rng.randint(nvert, 16)):
            a, b = rng.sample(range(nvert), 2)
            if deg[a] < 5 and deg[b] < 5: deg[a] += 1; deg[b] += 1; edges.append((a, b))
        nv = len(edges)
        charge = [rng.randint(0, 1) for _ in range(nvert)]
        if rng.random() < 0.5 and sum(charge) % 2 == 0: charge[0] ^= 1
        for v in range(nvert):
            vs = [i + 1 for i, e in enumerate(edges) if v in e]
            if vs: cl += xor_clauses(vs, charge[v])
            elif charge[v]: charge[v] = 0
    else:                                            # cardinality rows and columns of a 0/1 matrix
        r = rng.randint(3, 5); cells = {}
        for i in range(r):
            for j in rng.sample(range(r), rng.randint(2, min(4, r))):
                nv += 1; cells[(i, j)] = nv * rng.choice((1, 1, -1))
        for line in ([[cells[k] for k in cells if k[0] == i] for i in range(r)] + [[cells[k] for k in cells if k[1] == j] for j in range(r)]):
            if 2 <= len(line) <= 6:
                a = rng.randint(1, len(line) - 1)
                cl += exactly(line, a) if len(line) >= 4 and 2 <= a <= len(line) - 2 else xor_clauses([abs(x) for x in line], rng.randint(0, 1))
    if nv == 0: nv = 3
    # Damage and noise.
    if rng.random() < 0.25 and cl: del cl[rng.randrange(len(cl))]
    if rng.random() < 0.3:
        v = rng.randint(1, nv); cl.append([v * rng.choice((1, -1))])
    if rng.random() < 0.3 and nv >= 2:
        a, b = rng.sample(range(1, nv + 1), 2); s = rng.choice((1, -1)); cl += [[a, -s * b], [-a, s * b]]
    extra = rng.randint(0, 3) if rng.random() < 0.4 else 0
    for _ in range(extra):
        if rng.random() < 0.5 and nv < 18: nv += 1
        k = rng.randint(1, min(4, nv))
        cl.append([v * rng.choice((1, -1)) for v in rng.sample(range(1, nv + 1), k)])
    if rng.random() < 0.5:                           # flip the polarity of some variables everywhere
        flip = {v for v in range(1, nv + 1) if rng.random() < 0.4}
        cl = [[-l if abs(l) in flip else l for l in c] for c in cl]
    rng.shuffle(cl)
    for c in cl: rng.shuffle(c)
    return nv, cl

decided = sat = unsat = 0
for case in range(N):
    nv, cl = gen()
    path = os.path.join(TMP, 'c%d.cnf' % case)
    with open(path, 'w') as f:
        f.write('p cnf %d %d\n' % (nv, len(cl)))
        for c in cl: f.write(' '.join(map(str, c)) + ' 0\n')
    models = 0
    for m in range(1 << nv):
        if all(any(((m >> (abs(l) - 1)) & 1) == (l > 0) for l in c) for c in cl): models += 1; break
    r = subprocess.run([W, path, '--fast'], env=env, capture_output=True, text=True, timeout=120)
    lines = r.stdout.splitlines()
    verdict = [l[2:].strip() for l in lines if l.startswith('s ')]
    def die(msg):
        print('FAIL case %d seed %d: %s (%s)' % (case, SEED, msg, path)); sys.exit(1)
    if len(verdict) != 1 or verdict[0] not in ('SATISFIABLE', 'UNSATISFIABLE'): die('no single verdict: %r' % verdict)
    if (verdict[0] == 'SATISFIABLE') != (models > 0): die('verdict %s, enumerated %s' % (verdict[0], 'SAT' if models else 'UNSAT'))
    if models:
        sat += 1
        model = {abs(int(x)): int(x) > 0 for l in lines if l.startswith('v ') for x in l[2:].split() if x != '0'}
        if not all(any(model.get(abs(l), False) == (l > 0) for l in c) for c in cl): die('reported model does not satisfy the input')
    else: unsat += 1
    if any(('parity sum' in l or 'small variable set' in l) for l in lines if l.startswith('c mode')): decided += 1
if decided * 6 < N:
    print('FAIL: lane decided only %d of %d formulas' % (decided, N)); sys.exit(1)
print('parity sum: OK', {'runs': N, 'lane': decided, 'sat': sat, 'unsat': unsat})
