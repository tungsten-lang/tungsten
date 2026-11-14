#!/usr/bin/env python3
"""Differential test for the relayed pigeonhole count (lib/relay_count.w).

    WASSAT=<binary> [REF=cadical] [CASES=600] [SEED=1] python3 relay_count_test.py

Generates relativized pigeonhole formulas (P pigeons choose among R resting
places, a taken resting place chooses among H holes, two taken places may not
share a hole) with P up to 5, R up to 6 and H up to 4, and compares every verdict with
a reference solver (CaDiCaL by default); a reported model is replayed.

The formulas are damaged so that the count is often NOT justified: clauses of
every kind are dropped at random, pigeons and resting places get restricted
or widened choice lists, a choice clause gets a stray literal or shares one
with another pigeon, conflict clauses are added across different holes or
written with three literals, hole variables are shared between resting
places, random extra clauses and duplicates are mixed in, the sign of every
variable is scrambled, and clause and literal order are shuffled. A
refutation the lane reports for a formula the reference finds satisfiable
fails the test.

A run in which the lane rarely answers proves nothing, so the test also fails
when the lane decided fewer than a tenth of the formulas.
"""
import os, random, shutil, subprocess, sys, tempfile
W = os.environ.get('WASSAT') or sys.exit('set WASSAT=<binary>')
REF = shutil.which(os.environ.get('REF', 'cadical')) or sys.exit('reference solver not found (set REF=<solver>)')
N = int(os.environ.get('CASES', '600')); SEED = int(os.environ.get('SEED', '1'))
TMP = tempfile.mkdtemp(prefix='relay-count-')
rng = random.Random(SEED)
# The covering bound of threshold_cover.w answers some of these first; it has
# its own test, so it is switched off here.
env = dict(os.environ, WASSAT_BACKDOOR_TABLES='0', WASSAT_THRESHOLD_COVER='0')

def gen():
    P = rng.randint(2, 5)
    R = rng.randint(P, 6) if rng.random() < 0.8 else rng.randint(2, 5)
    H = rng.randint(1, P - 1) if rng.random() < 0.6 else rng.randint(1, 4)
    clean = rng.random() < 0.45          # no damage at all
    def keep(p): return clean or rng.random() < p
    def odd(p): return (not clean) and rng.random() < p
    nv = 0
    def new():
        nonlocal nv
        nv += 1; return nv
    p = [[new() for v in range(R)] for u in range(P)]
    r = [new() for v in range(R)]
    shared = odd(0.08)                   # one hole variable for all resting places
    hole = [new() for w in range(H)] if shared else None
    q = [[hole[w] if shared else new() for w in range(H)] for v in range(R)]
    cl = []
    for u in range(P):
        vs = list(range(R))
        if odd(0.2): vs = rng.sample(vs, rng.randint(1, R))
        c = [p[u][v] for v in vs]
        if odd(0.06): c.append(new())
        if odd(0.06): c.append(p[rng.randrange(P)][rng.randrange(R)])
        cl.append(c)
    for v in range(R):
        for a in range(P):
            for b in range(a + 1, P):
                if keep(0.96): cl.append([-p[a][v], -p[b][v]])
        for u in range(P):
            if keep(0.98): cl.append([-p[u][v], r[v]])
        ws = list(range(H))
        if odd(0.2): ws = rng.sample(ws, rng.randint(1, H))
        d = [-r[v]] + [q[v][w] for w in ws]
        if odd(0.05): d.append(q[rng.randrange(R)][rng.randrange(H)])
        if keep(0.98): cl.append(d)
    for a in range(R):
        for b in range(a + 1, R):
            for w in range(H):
                for x in range(H):
                    if (w == x and keep(0.97)) or (w != x and odd(0.04)):
                        c = [-r[a], -r[b], -q[a][w], -q[b][x]]
                        if odd(0.03): c.pop(rng.randrange(4))
                        cl.append(c)
    if odd(0.3):
        for _ in range(rng.randint(1, 3)):
            c = [rng.choice([1, -1]) * rng.randint(1, nv) for _ in range(rng.randint(1, 4))]
            cl.append(c)
    if odd(0.2): cl.append(list(rng.choice(cl)))
    # Scramble signs, then order.
    if rng.random() < 0.7:
        flip = {v: rng.random() < 0.5 for v in range(1, nv + 1)}
        cl = [[-x if flip[abs(x)] else x for x in c] for c in cl]
    for c in cl: rng.shuffle(c)
    rng.shuffle(cl)
    return nv, cl

def verdict_of(cmd, path, env=None):
    r = subprocess.run(cmd + [path], env=env, capture_output=True, text=True, timeout=120)
    lines = r.stdout.splitlines()
    return [l[2:].strip() for l in lines if l.startswith('s ')], lines

lane = sat = unsat = 0
for case in range(N):
    nv, cl = gen()
    path = os.path.join(TMP, 'c%d.cnf' % case)
    with open(path, 'w') as f:
        f.write('p cnf %d %d\n' % (nv, len(cl)))
        for c in cl: f.write(' '.join(map(str, c)) + ' 0\n')
    ref, _ = verdict_of([REF, '-q'], path)
    got, lines = verdict_of([W, '--fast'], path, env)
    def die(msg):
        print('FAIL case %d seed %d: %s (%s)' % (case, SEED, msg, path)); sys.exit(1)
    if len(ref) != 1 or ref[0] not in ('SATISFIABLE', 'UNSATISFIABLE'): die('reference gave %r' % ref)
    if got != ref: die('verdict %r, reference %r' % (got, ref))
    if ref[0] == 'SATISFIABLE':
        sat += 1
        model = {abs(int(x)): int(x) > 0 for l in lines if l.startswith('v ') for x in l[2:].split() if x != '0'}
        if not all(any(model.get(abs(l), False) == (l > 0) for l in c) for c in cl): die('reported model does not satisfy the input')
    else: unsat += 1
    if any('verified relayed count' in l for l in lines if l.startswith('c mode')): lane += 1
if lane * 10 < N:
    print('FAIL: lane decided only %d of %d formulas' % (lane, N)); sys.exit(1)
print('relay count: OK', {'runs': N, 'lane': lane, 'sat': sat, 'unsat': unsat})
