#!/usr/bin/env python3
"""Generate the benchmark instances: pigeonhole PHP(p,h) and random 3-SAT."""
import random, sys, os

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/satbench"
os.makedirs(OUT, exist_ok=True)


def php(p, h):
    """Pigeonhole: p pigeons into h holes. UNSAT when p > h."""
    v = lambda i, j: i * h + j + 1
    clauses = [[v(i, j) for j in range(h)] for i in range(p)]
    for j in range(h):
        for a in range(p):
            for b in range(a + 1, p):
                clauses.append([-v(a, j), -v(b, j)])
    return p * h, clauses


def write(name, nvars, clauses):
    with open(os.path.join(OUT, name), "w") as f:
        f.write(f"p cnf {nvars} {len(clauses)}\n")
        for c in clauses:
            f.write(" ".join(map(str, c)) + " 0\n")


for p, h in [(3, 2), (4, 3), (5, 4), (6, 5), (7, 6), (8, 7)]:
    nv, cl = php(p, h)
    write(f"php{p}{h}.cnf", nv, cl)
    print(f"php{p}{h}.cnf: {nv} vars, {len(cl)} clauses")

random.seed(7)
for nv in [20, 40]:
    m = int(nv * 4.0)          # clause/variable ratio below the ~4.26 threshold
    cl = []
    for _ in range(m):
        vs = random.sample(range(1, nv + 1), 3)
        cl.append([v if random.random() < 0.5 else -v for v in vs])
    write(f"rand3_{nv}.cnf", nv, cl)
    print(f"rand3_{nv}.cnf: {nv} vars, {m} clauses")
