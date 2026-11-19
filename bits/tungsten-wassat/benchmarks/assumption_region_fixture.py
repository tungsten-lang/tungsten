"""Generate equality or XOR CNF and a deterministic repeated-assumption trace."""

import argparse
from itertools import product
from pathlib import Path
import random


def encode(clauses, nvars, hidden):
    if not hidden:
        return clauses, nvars
    z, w = nvars + 1, nvars + 2
    return [c + [a, b] for c in clauses for a, b in product((z, -z), (w, -w))], w


def equality(size, queries, hidden, rng):
    boundary = list(range(1, size + 2))
    nvars = len(boundary)
    clauses = []
    for left, right in zip(boundary, boundary[1:]):
        edge, nvars = encode([[-left, right], [left, -right]], nvars, hidden)
        clauses.extend(edge)
    trace = []
    for i in range(queries):
        variables = rng.sample(boundary, min(len(boundary), 1 + i % 6))
        sign = rng.choice((-1, 1))
        query = [sign * v for v in variables]
        if i % 3 == 0 and len(query) > 1:
            query[-1] *= -1
        trace.append(query)
    return nvars, clauses, boundary, trace


def xor(size, queries, hidden, rng):
    boundary = list(range(1, 25))
    nvars = len(boundary)
    clauses, gates = [], []
    for _ in range(size):
        a, b = rng.sample(boundary, 2)
        y = nvars + 1
        relation = [[-a if va else a, -b if vb else b, y if va ^ vb else -y]
                    for va, vb in product((0, 1), repeat=2)]
        gate, nvars = encode(relation, y, hidden)
        clauses.extend(gate)
        gates.append((a, b, y))
    trace = []
    for i in range(queries):
        row = rng.getrandbits(len(boundary))
        query = [v if row & (1 << (v - 1)) else -v for v in boundary]
        if i % 3:
            a, b, y = rng.choice(gates)
            output = (query[a - 1] > 0) ^ (query[b - 1] > 0)
            query.append(y if output == (i % 3 == 1) else -y)
        trace.append(query)
    return nvars, clauses, boundary, trace


def row(literals):
    return " ".join([*map(str, literals), "0"]) + "\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--family", choices=("equality", "xor"), default="equality")
    parser.add_argument("--size", type=int, default=72, help="number of edges or gates")
    parser.add_argument("--queries", type=int, default=768)
    parser.add_argument("--seed", type=int, default=5)
    parser.add_argument("--hidden", action="store_true", help="encode each relation behind two free variables")
    args = parser.parse_args()
    if args.size < 1 or args.queries < 1:
        parser.error("size and queries must be positive")
    generate = equality if args.family == "equality" else xor
    nvars, clauses, boundary, trace = generate(args.size, args.queries, args.hidden, random.Random(args.seed))
    args.directory.mkdir(parents=True, exist_ok=True)
    with (args.directory / "formula.cnf").open("w") as cnf:
        cnf.write(f"p cnf {nvars} {len(clauses)}\n")
        cnf.writelines(map(row, clauses))
    with (args.directory / "queries.txt").open("w") as output:
        output.write(row(boundary))
        output.writelines(map(row, trace))
