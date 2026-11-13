#!/usr/bin/env python3
"""Differential test for the clique-coloring check (lib/coloring.w).

    WASSAT=<binary> [REF=cadical] [CASES=300] [SEED=1] python3 clique_coloring_test.py

A clique-coloring formula says: k slots hold k distinct vertices out of n,
any two of them joined by an edge, and the n vertices are colored with c < k
colors so that joined vertices differ. The check refutes it by reading that
every needed clause is present. Two kinds of case, every verdict compared with
a reference solver (CaDiCaL by default) and every reported model replayed:

  * small ones (k up to 7) with random damage: clauses dropped, duplicated,
    units and stray clauses added, the reference decides either way;
  * large ones (k from 9 to 12, where slot pairs outnumber the bits of a
    machine word) with exactly ONE needed clause removed and others of its
    kind written twice. These are satisfiable; a check that hashes slot pairs
    or counts clauses instead of distinct pairs calls them unsatisfiable.

Literal order and the order of the short clauses are shuffled. The test also
fails when the check decided fewer than a tenth of the formulas.
"""
import os, random, shutil, subprocess, sys, tempfile
W = os.environ.get('WASSAT') or sys.exit('set WASSAT=<binary>')
REF = shutil.which(os.environ.get('REF', 'cadical')) or sys.exit('reference solver not found (set REF=<solver>)')
N = int(os.environ.get('CASES', '300')); SEED = int(os.environ.get('SEED', '1'))
TMP = tempfile.mkdtemp(prefix='clique-coloring-')
rng = random.Random(SEED)
env = dict(os.environ, WASSAT_BACKDOOR_TABLES='0')

def formula(n, k, c):
    nv = 0
    def new():
        nonlocal nv
        nv += 1; return nv
    q = [[new() for v in range(n)] for s in range(k)]
    col = [[new() for r in range(c)] for v in range(n)]
    wide = [[q[s][v] for v in range(n)] for s in range(k)] + [[col[v][r] for r in range(c)] for v in range(n)]
    excl = [[-q[s][v], -q[t][v]] for v in range(n) for s in range(k) for t in range(s + 1, k)]
    force = []; differ = []
    for u in range(n):
        for v in range(u + 1, n):
            e = new()
            force += [[-q[s][u], -q[t][v], e] for s in range(k) for t in range(k) if s != t]
            differ += [[-e, -col[u][r], -col[v][r]] for r in range(c)]
    return nv, wide, [excl, force, differ]

def gen():
    if rng.random() < 0.4:
        # One needed clause missing, others doubled: satisfiable.
        k = rng.randint(9, 12); n = rng.randint(k + 1, 13); c = k - 1
        nv, wide, kinds = formula(n, k, c)
        kind = rng.randrange(3)
        kinds[kind].pop(rng.randrange(len(kinds[kind])))
        for _ in range(rng.randint(0, 3)): kinds[kind].append(list(rng.choice(kinds[kind])))
        rest = kinds[0] + kinds[1] + kinds[2]
        want = 'SATISFIABLE'
    else:
        k = rng.randint(5, 7); n = rng.randint(k + 1, 9); c = rng.randint(4, k - 1)
        nv, wide, kinds = formula(n, k, c)
        rest = kinds[0] + kinds[1] + kinds[2]
        want = None
        if rng.random() < 0.55:
            for _ in range(rng.randint(1, 2)):
                if rng.random() < 0.6: rest.pop(rng.randrange(len(rest)))
                if rng.random() < 0.5: rest.append(list(rng.choice(rest)))
                if rng.random() < 0.2: rest.append([rng.choice([1, -1]) * rng.randint(1, nv)])
                if rng.random() < 0.2: rest.append([rng.choice([1, -1]) * rng.randint(1, nv) for _ in range(rng.randint(2, 3))])
        elif rng.random() < 0.3:
            rest.append([rng.randint(1, k * n)])     # a slot fixed to a vertex
    # The check pairs the i-th coloring clause of the file with the i-th
    # vertex of the slot clauses, so the wide clauses keep their order.
    rng.shuffle(rest)
    cl = wide + rest
    for x in cl: rng.shuffle(x)
    return nv, cl, want

def verdict_of(cmd, path, env=None):
    r = subprocess.run(cmd + [path], env=env, capture_output=True, text=True, timeout=300)
    lines = r.stdout.splitlines()
    return [l[2:].strip() for l in lines if l.startswith('s ')], lines

lane = sat = unsat = 0
for case in range(N):
    nv, cl, want = gen()
    path = os.path.join(TMP, 'c%d.cnf' % case)
    with open(path, 'w') as f:
        f.write('p cnf %d %d\n' % (nv, len(cl)))
        for c in cl: f.write(' '.join(map(str, c)) + ' 0\n')
    ref, _ = verdict_of([REF, '-q'], path)
    got, lines = verdict_of([W, '--fast'], path, env)
    def die(msg):
        print('FAIL case %d seed %d: %s (%s)' % (case, SEED, msg, path)); sys.exit(1)
    if len(ref) != 1 or ref[0] not in ('SATISFIABLE', 'UNSATISFIABLE'): die('reference gave %r' % ref)
    if want and ref[0] != want: die('reference says %s for a formula built to be %s' % (ref[0], want))
    if got != ref: die('verdict %r, reference %r' % (got, ref))
    if ref[0] == 'SATISFIABLE':
        sat += 1
        model = {abs(int(x)): int(x) > 0 for l in lines if l.startswith('v ') for x in l[2:].split() if x != '0'}
        if not all(any(model.get(abs(l), False) == (l > 0) for l in c) for c in cl): die('reported model does not satisfy the input')
    else: unsat += 1
    if any('-clique / ' in l for l in lines if l.startswith('c mode')): lane += 1
if lane * 10 < N:
    print('FAIL: check decided only %d of %d formulas' % (lane, N)); sys.exit(1)
print('clique coloring: OK', {'runs': N, 'lane': lane, 'sat': sat, 'unsat': unsat})
