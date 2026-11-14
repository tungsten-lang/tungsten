#!/usr/bin/env python3
"""Differential test for the subgraph-isomorphism lane (lib/sgi.w), direct encoding.

    WASSAT=<binary> [REF=cadical] [CASES=300] [SEED=1] python3 sgi_test.py

A formula asks for an injective, edge-preserving map of a pattern graph on
4..9 vertices into a host graph on 30 vertices: one variable per (pattern
vertex, host vertex), a 30-literal clause per pattern vertex, at-most-one
binaries inside each, an injectivity binary per pair of pattern vertices and
host vertex, and a binary per pattern edge and host non-edge. Hosts are
sparse, bipartite or of bounded degree, and patterns get triangles and
high-degree vertices, so that both verdicts occur. The sign of every variable
is scrambled and the clauses are shuffled, as in the competition files.

Half of the formulas are damaged: binaries are dropped (the formula then says
less than "subgraph isomorphism", and a lane that fills the gap in refutes a
satisfiable formula), duplicated, or joined by stray clauses. Every verdict is
compared with a reference solver (CaDiCaL by default) and every reported
model is replayed. The test fails when the lane decided fewer than a tenth of
the formulas.
"""
import os, random, shutil, subprocess, sys, tempfile
W = os.environ.get('WASSAT') or sys.exit('set WASSAT=<binary>')
REF = shutil.which(os.environ.get('REF', 'cadical')) or sys.exit('reference solver not found (set REF=<solver>)')
N = int(os.environ.get('CASES', '300')); SEED = int(os.environ.get('SEED', '1'))
TMP = tempfile.mkdtemp(prefix='sgi-')
rng = random.Random(SEED)
env = dict(os.environ, WASSAT_BACKDOOR_TABLES='0')
H = 30

def gen():
    np_ = rng.randint(4, 9)
    # Host.
    hadj = [[False] * H for _ in range(H)]
    kind = rng.choice(('bipartite', 'sparse', 'degree'))
    if kind == 'bipartite':
        side = [rng.random() < 0.5 for _ in range(H)]
        for a in range(H):
            for b in range(a + 1, H):
                if side[a] != side[b] and rng.random() < 0.25: hadj[a][b] = hadj[b][a] = True
    elif kind == 'sparse':
        for a in range(H):
            for b in range(a + 1, H):
                if rng.random() < rng.choice((0.05, 0.1, 0.2)): hadj[a][b] = hadj[b][a] = True
    else:
        cap = rng.randint(2, 4); deg = [0] * H
        pairs = [(a, b) for a in range(H) for b in range(a + 1, H)]; rng.shuffle(pairs)
        for a, b in pairs:
            if deg[a] < cap and deg[b] < cap and rng.random() < 0.5:
                hadj[a][b] = hadj[b][a] = True; deg[a] += 1; deg[b] += 1
    # Pattern.
    pe = set()
    for a in range(np_):
        for b in range(a + 1, np_):
            if rng.random() < rng.choice((0.2, 0.35, 0.5)): pe.add((a, b))
    if rng.random() < 0.4: pe |= {(0, 1), (1, 2), (0, 2)}
    if rng.random() < 0.3:
        for b in range(1, min(np_, rng.randint(4, 6))): pe.add((0, b))
    x = lambda p, h: p * H + h + 1
    wide = [[x(p, h) for h in range(H)] for p in range(np_)]
    amo = [[-x(p, h), -x(p, k)] for p in range(np_) for h in range(H) for k in range(h + 1, H)]
    inj = [[-x(p, h), -x(q, h)] for p in range(np_) for q in range(p + 1, np_) for h in range(H)]
    adj = [[-x(p, h), -x(q, k)] for (p, q) in pe for h in range(H) for k in range(H) if h != k and not hadj[h][k]]
    nv = np_ * H
    if rng.random() < 0.5:
        for part in (amo, inj, adj):
            for _ in range(rng.randint(0, 3)):
                if part and rng.random() < 0.6: part.pop(rng.randrange(len(part)))
            if part and rng.random() < 0.3: part.append(list(rng.choice(part)))
        if rng.random() < 0.3:
            wide.append([rng.randint(1, nv) * rng.choice((1, -1)) for _ in range(rng.randint(2, 3))])
    cl = wide + amo + inj + adj
    flip = {v: rng.random() < 0.5 for v in range(1, nv + 1)}
    cl = [[-l if flip[abs(l)] else l for l in c] for c in cl]
    for c in cl: rng.shuffle(c)
    rng.shuffle(cl)
    return nv, cl

def verdict_of(cmd, path, env=None):
    r = subprocess.run(cmd + [path], env=env, capture_output=True, text=True, timeout=300)
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
        model = {abs(int(t)): int(t) > 0 for l in lines if l.startswith('v ') for t in l[2:].split() if t != '0'}
        if not all(any(model.get(abs(l), False) == (l > 0) for l in c) for c in cl): die('reported model does not satisfy the input')
    else: unsat += 1
    if any(l.startswith('c lane: sgi_mcsplit') for l in lines): lane += 1
if lane * 10 < N:
    print('FAIL: lane decided only %d of %d formulas' % (lane, N)); sys.exit(1)
print('sgi: OK', {'runs': N, 'lane': lane, 'sat': sat, 'unsat': unsat})
