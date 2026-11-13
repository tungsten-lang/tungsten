#!/usr/bin/env python3
"""Exhaustive-model test for the gate congruence closure lane (lib/gate_closure.w).

    WASSAT=<binary> [CASES=600] [SEED=1] python3 gate_closure_test.py

Generates small Tseitin circuits (AND, OR, XOR and if-then-else gates with
repeated and perturbed structure, negated outputs, random units, binary
equivalences and stray clauses), at most 15 variables each, and runs the
binary with WASSAT_GATE_CLOSURE_DUMP=1 so the lane prints every clause it
appends. For each formula, against ALL models found by enumeration:

  * every appended clause must hold in every model of the input;
  * the verdict must be the enumerated one;
  * a reported model must be one of the enumerated models.

A run in which the lane never fires proves nothing, so the test also fails
when fewer than half of the formulas were extended.
"""
import os, random, subprocess, sys, itertools, tempfile
W = os.environ.get('WASSAT') or sys.exit('set WASSAT=<binary>')
N = int(os.environ.get('CASES', '600')); SEED = int(os.environ.get('SEED', '1'))
TMP = tempfile.mkdtemp(prefix='gate-closure-')
rng = random.Random(SEED)
env = dict(os.environ, WASSAT_BACKDOOR_TABLES='0', WASSAT_GATE_CLOSURE_DUMP='1')
def gen():
    nin = rng.randint(2, 5); nv = nin; cl = []
    sigs = []
    ngate = rng.randint(4, 11)
    for _ in range(ngate):
        nv += 1; out = nv
        pool = list(range(1, out))
        if sigs and rng.random() < 0.45:
            ty, ins = rng.choice(sigs)          # duplicate structure
            if rng.random() < 0.3:              # perturb one input to an equivalent-looking one
                ins = list(ins); ins[rng.randrange(len(ins))] = rng.choice(pool) * rng.choice((1, -1))
        else:
            ty = rng.choice('AAXXIIO')
            k = 3 if ty == 'I' else rng.choice((2, 2, 3, 4) if ty != 'X' else (2, 2, 3, 4))
            ins = [rng.choice(pool) * rng.choice((1, -1)) for _ in range(k)]
        if ty == 'I' and len(ins) != 3: ty = 'A'
        ins = tuple(ins); sigs.append((ty, ins))
        o = out * rng.choice((1, 1, 1, -1))
        if ty == 'A':
            cl.append([o] + [-x for x in ins]); cl += [[-o, x] for x in ins]
        elif ty == 'O':
            cl.append([-o] + list(ins)); cl += [[o, -x] for x in ins]
        elif ty == 'X':
            vs = [o] + list(ins)
            if len(set(abs(x) for x in vs)) == len(vs) or rng.random() < 0.5:
                for signs in itertools.product((1, -1), repeat=len(vs)):
                    if sum(1 for s in signs if s < 0) % 2 == 1:   # o ^ ins... = 0 : forbid odd parity assignments
                        cl.append([-s * v for s, v in zip(signs, vs)])
            else:
                cl.append([o] + [-x for x in ins]); cl += [[-o, x] for x in ins]
        else:
            c, t, e = ins
            cl += [[-c, -t, o], [-c, t, -o], [c, -e, o], [c, e, -o]]
    for _ in range(rng.randint(0, 3)): cl.append([rng.randint(1, nv) * rng.choice((1, -1))])
    for _ in range(rng.randint(0, 2)):
        a, b = rng.randint(1, nv), rng.randint(1, nv); s = rng.choice((1, -1))
        cl += [[-a, s * b], [a, -s * b]]
    for _ in range(rng.randint(0, 3)):
        cl.append([rng.randint(1, nv) * rng.choice((1, -1)) for _ in range(rng.choice((2, 3, 3, 4)))])
    while nv < 8: nv += 1
    while len(cl) < 8: cl.append([nv, -nv, 1])
    for c in cl: rng.shuffle(c)
    rng.shuffle(cl)
    return nv, cl
def models(nv, cl):
    out = []
    for m in range(1 << nv):
        ok = True
        for c in cl:
            if not any(((m >> (abs(x) - 1)) & 1) == (1 if x > 0 else 0) for x in c): ok = False; break
        if ok: out.append(m)
    return out
stats = dict(runs=0, lifted=0, clauses=0, sat=0, unsat=0)
for it in range(N):
    nv, cl = gen()
    if nv > 15: continue
    path = os.path.join(TMP, 'case.cnf')
    with open(path, 'w') as f:
        f.write(f'p cnf {nv} {len(cl)}\n'); f.writelines(' '.join(map(str, c)) + ' 0\n' for c in cl)
    o = subprocess.run([W, path, '--fast'], env=env, capture_output=True, text=True, timeout=60).stdout
    ms = models(nv, cl)
    verdict = [l for l in o.splitlines() if l.startswith('s ')]
    exp = 's SATISFIABLE' if ms else 's UNSATISFIABLE'
    if verdict != [exp]:
        print('VERDICT MISMATCH', it, verdict, exp); print('kept:', path); sys.exit(1)
    if ms:
        v = [int(x) for l in o.splitlines() if l.startswith('v ') for x in l[2:].split() if x != '0']
        mm = sum(1 << (x - 1) for x in v if x > 0 and x <= nv)
        if mm not in set(ms): print('MODEL WRONG', it); print('kept:', path); sys.exit(1)
    added = [[int(x) for x in l.split()[2:]] for l in o.splitlines() if l.startswith('c gate-closure-clause')]
    stats['runs'] += 1; stats['sat' if ms else 'unsat'] += 1
    if added: stats['lifted'] += 1; stats['clauses'] += len(added)
    for c in added:
        for m in ms:
            if not any(((m >> (abs(x) - 1)) & 1) == (1 if x > 0 else 0) for x in c):
                print('NOT IMPLIED', it, c); print('kept:', path); sys.exit(1)
if stats['lifted'] * 2 < stats['runs']: print('FAIL: lane rarely fired', stats); sys.exit(1)
print('gate closure: OK', stats)
