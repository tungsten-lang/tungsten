#!/usr/bin/env python3
"""Differential test for the demand-against-room lane (lib/threshold_cover.w).

    WASSAT=<binary> [REF=cadical] [CASES=600] [SEED=1] python3 threshold_cover_test.py

Generates formulas over 5..12 leaf variables and compares
every verdict with a reference solver (CaDiCaL by default); a reported model
is replayed. Four kinds of case:

  * a path counter "exactly K of the leaves": one node per (position, count),
    exactly one node true per position, each node tied to its neighbours in
    both directions, the last position pinned by unit clauses (the encoding
    of the 1-ET inputs of SAT Competition 2025). The leaves carry a random
    exclusion graph whose independence number the generator knows, and K is
    taken around it, so the exact bound is tested on both sides of the line.
    Clauses are dropped, nodes are killed or revived by unit clauses, and
    stray clauses are added;

  * a proper threshold diagram "at least K of the leaves" in the MiniSat+
    style (if-then-else nodes with or without the third clause, conjunctions
    at the bottom, optional "none of the rest" terminals of an equality), over
    a random leaf order, with K around the number of exclusive groups;
  * positive clauses to be covered by at most one leaf per exclusive group
    (the covering bound, wassat_cover_bound_unsat);
  * a random DAG of conjunction, disjunction and if-then-else nodes whose
    children are picked without regard to order, so that supports overlap, a
    variable is read twice on a path, and definitions can depend on each
    other in a cycle.

The exclusions are a partition into groups with pairs randomly removed
(so a group is no longer one), added across groups, and duplicated; random
extra clauses and units are mixed in. A refutation the lane reports for a
formula the reference finds satisfiable fails the test.

A run in which the lane rarely answers proves nothing, so the test also fails
when the lane decided fewer than a tenth of the formulas.
"""
import os, random, shutil, subprocess, sys, tempfile
W = os.environ.get('WASSAT') or sys.exit('set WASSAT=<binary>')
REF = shutil.which(os.environ.get('REF', 'cadical')) or sys.exit('reference solver not found (set REF=<solver>)')
N = int(os.environ.get('CASES', '600')); SEED = int(os.environ.get('SEED', '1'))
TMP = tempfile.mkdtemp(prefix='threshold-cover-')
rng = random.Random(SEED)
env = dict(os.environ, WASSAT_BACKDOOR_TABLES='0')

def alpha(n, edges):
    best = 0
    for m in range(1 << n):
        if all(not ((m >> a) & 1 and (m >> b) & 1) for a, b in edges):
            best = max(best, bin(m).count('1'))
    return best

def gen_path():
    n = rng.randint(4, 10); cl = []; nv = n
    # Exclusion graph: random edges, or odd cycles.
    edges = set()
    if rng.random() < 0.5:
        # Odd cycles: a cycle of 5 holds 2, of 7 holds 3, but no cover by
        # exclusive groups gets below 3 and 4. Only the exact bound sees it.
        n = 0
        for _ in range(rng.randint(1, 2)):
            k = rng.choice((5, 5, 7))
            for i in range(k): edges.add((n + i, n + (i + 1) % k) if i + 1 < k else (n, n + k - 1))
            n += k
        n += rng.randint(0, 2); nv = n
        if rng.random() < 0.3:
            a, b = rng.sample(range(n), 2); edges.add((min(a, b), max(a, b)))
    else:
        for _ in range(rng.randint(n // 2, 2 * n)):
            a, b = rng.sample(range(n), 2); edges.add((min(a, b), max(a, b)))
    al = alpha(n, edges)
    K = max(1, min(n, al + rng.choice((-1, 0, 0, 1, 1, 2))))
    for a, b in edges: cl.append([-(a + 1), -(b + 1)])
    node = {}
    for i in range(1, n + 1):
        for j in range(0, min(i, K) + 1):
            nv += 1; node[(i, j)] = nv
    damaged = rng.random() < 0.5
    def put(c):
        if not damaged or rng.random() < 0.97: cl.append(c)
    # Position 1.
    put([1, node[(1, 0)]]); put([node[(1, 0)], node[(1, 1)]]); put([-node[(1, 0)], -node[(1, 1)]])
    for i in range(2, n + 1):
        x = i
        layer = [node[(i, j)] for j in range(0, min(i, K) + 1)]
        put(layer[:])
        for a in range(len(layer)):
            for b in range(a + 1, len(layer)): put([-layer[a], -layer[b]])
        for j in range(0, min(i - 1, K) + 1):
            p = node[(i - 1, j)]
            lo = node[(i, j)]
            put([-p, x, lo]); put([-lo, x, p]); put([-lo, -p, -x])
            if (i, j + 1) in node:
                hi = node[(i, j + 1)]
                put([-p, -x, hi]); put([-hi, -x, p]); put([-hi, -p, x])
            else:
                put([-p, -x])                      # the count may not pass K
    # The last position: exactly K.
    for j in range(0, min(n, K) + 1):
        put([node[(n, j)]] if j == K else [-node[(n, j)]])
    # Nodes from which K is out of reach.
    for (i, j), v in node.items():
        if j + (n - i) < K and rng.random() < 0.8: put([-v])
    if damaged:
        for _ in range(rng.randint(0, 2)):
            v = rng.choice(list(node.values())); cl.append([v * rng.choice((1, -1))])
        for _ in range(rng.randint(0, 2)):
            cl.append([rng.randint(1, nv) * rng.choice((1, -1)) for _ in range(rng.randint(2, 3))])
        if rng.random() < 0.3: cl.append(list(rng.choice(cl)))
    for c in cl: rng.shuffle(c)
    if rng.random() < 0.5: rng.shuffle(cl)
    return nv, cl

def gen():
    if rng.random() < 0.3: return gen_path()
    nl = rng.randint(5, 12); leaves = list(range(1, nl + 1)); nv = nl; cl = []
    def new():
        nonlocal nv
        nv += 1; return nv
    # Exclusive groups, then damage.
    order = leaves[:]; rng.shuffle(order); groups = []; i = 0
    while i < nl:
        k = rng.randint(1, 4); groups.append(order[i:i + k]); i += k
    for g in groups:
        for a in range(len(g)):
            for b in range(a + 1, len(g)):
                if rng.random() < 0.94: cl.append([-g[a], -g[b]])
                if rng.random() < 0.05: cl.append([-g[b], -g[a]])
    for _ in range(rng.randint(0, 2)):
        a, b = rng.sample(leaves, 2); cl.append([-a, -b])
    if rng.random() < 0.25:
        # Covering: positive clauses over the leaves, to be hit by at most one
        # leaf per group (the second lane of the file). Built so that pairs of
        # different groups often share clauses; some clauses repeat a literal
        # or are duplicated.
        root = None
        if rng.random() < 0.6:
            # Near the bound: r rows of c cells (c prime), one exclusive group
            # per row, and the lines of some directions of the plane over Zc
            # as clauses, so two cells of different rows share at most a line.
            # Then clauses are dropped or widened and exclusions removed.
            c = rng.choice((3, 5)); r = rng.randint(2, c); cell = {}
            for i in range(r):
                for j in range(c): cell[(i, j)] = new()
            for i in range(r):
                for j in range(c):
                    for k in range(j + 1, c):
                        if rng.random() < 0.97: cl.append([-cell[(i, j)], -cell[(i, k)]])
            lines = []
            for slope in rng.sample(range(c), rng.randint(1, c)):
                for b in range(c): lines.append([cell[(i, (slope * i + b) % c)] for i in range(r)])
            for _ in range(rng.choice((0, 0, 1, 2))):
                if len(lines) > 1: del lines[rng.randrange(len(lines))]
            for ln in lines:
                if rng.random() < 0.05: ln.append(rng.choice(list(cell.values())))
            cl += lines
        target = 0 if cl and rng.random() < 0.6 else rng.randint(len(groups), 6 * len(groups) + 2)
        wide = rng.random() < 0.5
        for _ in range(target):
            # Narrow clauses (two or three groups) leave pairs that share
            # nothing; wide ones make every pair overlap.
            c = [rng.choice(g) for g in groups if rng.random() < (0.8 if wide else 0.3)]
            if len(c) >= 2:
                if rng.random() < 0.1: c.append(c[0])
                cl.append(c)
                if rng.random() < 0.08: cl.append(list(c))
    elif rng.random() < 0.55:
        # Threshold diagram over a random order: node(i, j) = at least j of order[i:].
        xs = leaves[:]; rng.shuffle(xs)
        K = max(1, min(nl, len(groups) + rng.choice((-1, 0, 1, 1, 2))))
        third = rng.random() < 0.6; equality = rng.random() < 0.4
        memo = {}
        def node(i, j):
            rest = nl - i
            if j <= 0:
                if not equality: return None                      # true: nothing to assert
                key = ('z', i)
                if key not in memo:
                    v = new(); memo[key] = v
                    for x in xs[i:]: cl.append([-v, -x])
                return memo[key]
            if j > rest: return 0                                  # false
            if (i, j) in memo: return memo[(i, j)]
            v = new(); memo[(i, j)] = v
            if j == rest:
                for x in xs[i:]: cl.append([-v, x])
                return v
            hi = node(i + 1, j - 1); lo = node(i + 1, j); x = xs[i]
            if lo == 0: cl.append([-v, x])
            elif lo is not None:
                cl.append([-v, x, lo])
            if hi is not None and hi != 0: cl.append([-v, -x, hi])
            if third and lo not in (None, 0) and hi not in (None, 0): cl.append([-v, lo, hi])
            return v
        root = node(0, K)
    else:
        pool = leaves[:]; root = None
        for _ in range(rng.randint(3, 14)):
            v = new(); t = rng.random()
            if t < 0.35:
                for p in rng.sample(pool, min(len(pool), rng.randint(1, 3))): cl.append([-v, p])
            elif t < 0.55:
                a, b = rng.sample(pool, 2); cl.append([-v, a, b])
            else:
                x = rng.choice(pool if rng.random() < 0.15 else leaves); lo, hi = rng.choice(pool), rng.choice(pool)
                if lo != x: cl.append([-v, x, lo])
                if hi != x: cl.append([-v, -x, hi])
                if rng.random() < 0.5 and lo != hi: cl.append([-v, lo, hi])
            pool.append(v)
            if rng.random() < 0.08 and len(pool) > nl + 1:           # a definition that depends on a later one
                u = rng.choice(pool[nl:]); cl.append([-u, v])
        root = pool[-1]
    if root: cl.append([root])
    for _ in range(rng.randint(0, 2) if rng.random() < 0.3 else 0):
        k = rng.randint(1, 3); cl.append([v * rng.choice((1, -1)) for v in rng.sample(range(1, nv + 1), min(k, nv))])
    rng.shuffle(cl)
    for c in cl: rng.shuffle(c)
    return nv, [c for c in cl if c]

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
    if any(('verified count' in l or 'verified cover count' in l) for l in lines if l.startswith('c mode')): lane += 1
if lane * 10 < N:
    print('FAIL: lane decided only %d of %d formulas' % (lane, N)); sys.exit(1)
print('threshold cover: OK', {'runs': N, 'lane': lane, 'sat': sat, 'unsat': unsat})
