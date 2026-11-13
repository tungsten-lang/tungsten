#!/usr/bin/env python3
"""Exhaustive-model test for the bounded variable addition lane (lib/bva.w).

    WASSAT=<binary> [CASES=300] [SEED=1] python3 bva_test.py

Generates formulas of 9..16 variables made mostly of clause products (every
clause Ri | mj for a set of literals m and a set of one- or two-literal rests
R), pairwise at-most-one groups, damaged products, duplicates, tautologies,
repeated literals, long clauses and random clauses; about half are built
around a planted model. The binary runs with WASSAT_BVA_DUMP=1, so the lane
prints the formula it factored (and keeps every reduction, where a normal
run keeps only an eightfold reduction of a dense formula). For each case:

  * the factored formula, with its fresh variables eliminated again by
    resolution over truth tables of the input's variables, must have EXACTLY
    the input's models (both soundness directions, for all 2^n assignments);
  * the verdict must be the enumerated one;
  * a reported model must satisfy the input.

A run in which the lane rarely fires proves nothing, so the test also fails
when fewer than a third of the formulas were factored.
"""
import os, random, subprocess, sys, tempfile
W = os.environ.get('WASSAT') or sys.exit('set WASSAT=<binary>')
N = int(os.environ.get('CASES', '300')); SEED = int(os.environ.get('SEED', '1'))
TMP = tempfile.mkdtemp(prefix='bva-')
rng = random.Random(SEED)
env = dict(os.environ, WASSAT_BACKDOOR_TABLES='0', WASSAT_BVA_DUMP='1')

def gen():
    # Two regimes. Dense: many overlapping products, few or no models (the
    # verdict path). Sparse: a handful of products over more variables, so the
    # formula has many models and a wrong clause in the factored formula
    # changes the model set. Measured by corrupting one clause of a dump
    # (dropping it or flipping a literal): caught 168 times in 267 when the
    # input has ten or more models, 5 times in 177 when it has none.
    sparse = rng.random() < 0.6
    nv = rng.randint(11, 16) if sparse else rng.randint(9, 13)
    plant = [rng.random() < 0.5 for _ in range(nv + 1)] if rng.random() < 0.55 else None
    holds = lambda c: plant is None or any((l > 0) == plant[abs(l)] for l in c)
    lit = lambda v: v if (plant is None or plant[v]) else -v      # true under the plant
    cl = []
    for _ in range(rng.randint(1, 4) if sparse else rng.randint(8, 26)):
        vs = rng.sample(range(1, nv + 1), rng.randint(4, min(nv, 11)))
        k = rng.randint(2, max(2, min(7, len(vs) - 2)))
        ms, rv = vs[:k], vs[k:]
        mode = rng.random()
        if plant is not None and mode < 0.5: ml = [lit(v) for v in ms]                 # every m true
        else: ml = [v * rng.choice((1, -1)) for v in ms]
        rests = set()
        for _ in range(rng.randint(3, 9) if sparse else rng.randint(3, 28)):
            r = rng.sample(rv, min(len(rv), rng.choice((1, 2, 2))))
            r = tuple(sorted(lit(v) if (plant is not None and mode >= 0.5) else v * rng.choice((1, -1)) for v in r))
            rests.add(r)
        for r in rests:
            for m in ml:
                c = list(r) + [m]
                if rng.random() < 0.02: continue                                         # damaged product
                if holds(c):
                    rng.shuffle(c); cl.append(c)
                    if rng.random() < 0.02: cl.append(list(c))                           # duplicate
    for _ in range(rng.randint(0, 1) if sparse else rng.randint(0, 3)):                 # at-most-one groups
        g = [-lit(v) if plant is not None else v * rng.choice((1, -1)) for v in rng.sample(range(1, nv + 1), rng.randint(4, 8))]
        for i in range(len(g)):
            for j in range(i + 1, len(g)):
                c = [g[i], g[j]]
                if holds(c): cl.append(c)
    for _ in range(rng.randint(0, 6) if sparse else rng.randint(0, 30)):
        c = [v * rng.choice((1, -1)) for v in rng.sample(range(1, nv + 1), rng.choice((1, 2, 2, 3, 3, 4, 5, 6)))]
        if rng.random() < 0.1 and len(c) >= 2: c[1] = rng.choice((c[0], -c[0]))          # repeated literal / tautology
        if holds(c): cl.append(c)
    rng.shuffle(cl)
    return nv, cl

def tables(nv):
    full = (1 << (1 << nv)) - 1; t = {}
    for v in range(1, nv + 1):
        blk = (1 << (1 << (v - 1))) - 1; m = 0; period = 1 << v
        for s in range(1 << (v - 1), 1 << nv, period): m |= blk << s
        t[v] = m; t[-v] = full & ~m
    return full, t

def project(nv, lifted_nv, lifted):
    """Truth table (over the input's variables) of: exists fresh variables . lifted."""
    full, t = tables(nv)
    cs = []
    for c in lifted:
        m = 0; xs = set()
        for l in c:
            if abs(l) <= nv: m |= t[l]
            else: xs.add(l)
        if any(-x in xs for x in xs) or m == full: continue
        cs.append((m, frozenset(xs)))
    for x in range(lifted_nv, nv, -1):
        pos = [c for c in cs if x in c[1]]; neg = [c for c in cs if -x in c[1]]
        cs = [c for c in cs if x not in c[1] and -x not in c[1]]
        seen = set()
        for pm, px in pos:
            for nm, nx in neg:
                m = pm | nm; xs = (px | nx) - {x, -x}
                if m == full or any(-y in xs for y in xs): continue
                if (m, xs) not in seen: seen.add((m, xs)); cs.append((m, xs))
        if len(cs) > 200000: raise RuntimeError('elimination blew up')
    out = full
    for m, xs in cs:
        assert not xs
        out &= m
    return out

fired = sat = unsat = 0
for case in range(N):
    nv, cl = gen()
    path = os.path.join(TMP, 'c%d.cnf' % case)
    with open(path, 'w') as f:
        f.write('p cnf %d %d\n' % (nv, len(cl)))
        for c in cl: f.write(' '.join(map(str, c)) + ' 0\n')
    full, t = tables(nv)
    truth = full
    for c in cl:
        m = 0
        for l in c: m |= t[l]
        truth &= m
    r = subprocess.run([W, path, '--fast'], env=env, capture_output=True, text=True, timeout=120)
    lines = r.stdout.splitlines()
    dump = [l[10:] for l in lines if l.startswith('c bva-cnf ')]
    verdict = [l[2:].strip() for l in lines if l.startswith('s ')]
    def die(msg):
        print('FAIL case %d seed %d: %s (%s)' % (case, SEED, msg, path)); sys.exit(1)
    if len(verdict) != 1: die('no single verdict: %r' % verdict)
    if (verdict[0] == 'SATISFIABLE') != (truth != 0) or verdict[0] not in ('SATISFIABLE', 'UNSATISFIABLE'): die('verdict %s, enumerated %s' % (verdict[0], 'SAT' if truth else 'UNSAT'))
    if truth:
        sat += 1
        model = [int(x) for l in lines if l.startswith('v ') for x in l[2:].split() if x != '0']
        idx = sum(1 << (abs(l) - 1) for l in model if l > 0 and abs(l) <= nv)
        if len(set(abs(l) for l in model)) < nv or not (truth >> idx) & 1: die('reported model does not satisfy the input')
    else: unsat += 1
    if dump:
        fired += 1
        head = dump[0].split(); lnv = int(head[2]); lifted = [[int(x) for x in l.split()[:-1]] for l in dump[1:]]
        if len(lifted) != int(head[3]): die('dump has %d clauses, header says %s' % (len(lifted), head[3]))
        if lnv <= nv or len(lifted) >= len(cl): die('kept a formula that is not smaller: %d vars %d clauses from %d/%d' % (lnv, len(lifted), nv, len(cl)))
        if project(nv, lnv, lifted) != truth: die('factored formula does not have the input\'s models')
        if not any('bounded variable addition' in l for l in lines if l.startswith('c mode')): die('factored but verdict came from elsewhere')
if fired * 3 < N:
    print('FAIL: lane factored only %d of %d formulas' % (fired, N)); sys.exit(1)
print('bva: OK', {'runs': N, 'factored': fired, 'sat': sat, 'unsat': unsat})
