#!/usr/bin/env python3
"""Opt-in proof-producing Wassat gate-miter experiment. See README.md."""
import argparse
from itertools import product
import os
from pathlib import Path
import random
import shutil
import subprocess
import sys
import tempfile
import time

WIDTH = 1024
MASK = (1 << WIDTH) - 1


def gate_table(output, rows):
    inputs = sorted({abs(v) for row in rows for v in row[1:]})
    if output in inputs or len(inputs) > 4:
        return None
    table = []
    for bits in product((False, True), repeat=len(inputs)):
        values = dict(zip(inputs, bits))
        permitted = []
        for bit in (False, True):
            values[output] = bit
            if all(any(values[abs(v)] == (v > 0) for v in row) for row in rows):
                permitted.append(bit)
        if len(permitted) != 1:
            return None
        table.append(permitted[0])
    return inputs, table


def recognize(path, max_gates):
    # This specialist consumes grouped Tseitin definitions. Unsupported DIMACS
    # layouts are handed directly to Wassat, including very long clauses.
    with path.open('rb') as source:
        nvars = None
        rows = []
        gates = {}
        group = []
        previous = None
        units = []
        root = None
        for _line in iter(lambda: source.readline(8193), b''):
            if len(_line) > 8192:
                return None
            line = _line.strip()
            if not line or line.startswith(b'c'):
                continue
            if nvars is None:
                fields = line.split()
                if len(fields) != 4 or fields[:2] != [b'p', b'cnf']:
                    return None
                nvars, declared = map(int, fields[2:])
                continue
            literals = tuple(map(int, line.split()))
            if not 2 <= len(literals) <= 6 or literals[-1] != 0:
                return None
            row = literals[:-1]
            if any(lit == 0 or abs(lit) > nvars for lit in row):
                return None
            if len(row) == 1:
                if root is None:
                    return None
                if len(units) > 4 * max_gates:
                    return None
                units.append(row[0])
            else:
                out = abs(row[0])
                if root is None:
                    root = out
                # A two-input XOR/XNOR needs its four ternary truth-table rows.
                if previous != out:
                    if previous is not None:
                        gate = gate_table(previous, group)
                        if gate is None:
                            return None
                        if previous == root and gate[1] not in ([0, 1, 1, 0], [1, 0, 0, 1]):
                            return None
                        gates[previous] = gate
                    if out in gates or len(gates) >= max_gates:
                        return None
                    previous, group = out, []
                if out == root and (len(row) != 3 or len(group) >= 4):
                    return None
                group.append(row)
                if len(group) > 16:
                    return None
            rows.append(row)
    if root is None or len(rows) != declared:
        return None
    gates[previous] = gate_table(previous, group)
    root_gate = gates[root]
    if gates[previous] is None or root_gate is None or root_gate[1] not in ([0, 1, 1, 0], [1, 0, 0, 1]):
        return None
    assertions = [u for u in units if abs(u) in gates]
    if len(assertions) != 1 or abs(assertions[0]) != root:
        return None
    return nvars, rows, gates, units, assertions[0]


def fanin(gates, root):
    cone = set()
    queue = [root]
    while queue:
        v = queue.pop()
        if v not in cone:
            cone.add(v)
            if v in gates:
                queue.extend(gates[v][0])
    return cone


def schedule(gates, units, assertion):
    free = sorted({u for args, _ in gates.values() for u in args} - gates.keys())
    rng = random.Random(846)
    signatures = {v: rng.getrandbits(WIDTH) for v in free}
    depth = dict.fromkeys(free, 0)
    for lit in units:
        if abs(lit) != abs(assertion):
            signatures[abs(lit)] = MASK if lit > 0 else 0
    # Evaluate only the asserted cone. Cycles and detached definitions decline.
    visiting = set()
    stack = [(abs(assertion), False)]
    while stack:
        v, finish = stack.pop()
        if v in signatures:
            continue
        inputs, table = gates[v]
        if not finish:
            if v in visiting:
                return None
            visiting.add(v)
            stack.append((v, True))
            stack.extend((u, False) for u in inputs if u not in signatures)
            continue
        visiting.remove(v)
        signature = 0
        for i, value in enumerate(table):
            if value:
                term = MASK
                for j, u in enumerate(inputs):
                    sig = signatures[u]
                    term &= sig if i & (1 << (len(inputs) - 1 - j)) else ~sig
                signature |= term
        signatures[v] = signature
        depth[v] = 1 + max(depth[u] for u in inputs)
    root = abs(assertion)
    if any(v not in depth for v in gates) or signatures[root] != (0 if assertion > 0 else MASK):
        return None
    reps = {}
    queries = []
    for v in sorted(depth, key=lambda u: (depth[u], u)):
        if v == root:
            continue
        sig = signatures[v]
        key = min(sig, MASK ^ sig)
        other = reps.setdefault(key, v)
        if other != v:
            queries.append((v, other if sig == signatures[other] else -other))
    a, b = gates[root][0]
    if signatures[a] == (MASK ^ signatures[b]):
        b = -b
    elif signatures[a] != signatures[b]:
        return None
    # Make the final query the exact comparator relation regardless of which
    # internal representative was selected. A tie in depth can reverse a pair.
    queries = [(u, v) for u, v in queries if {u, abs(v)} != {a, abs(b)}]
    left = fanin(gates, a)
    right = fanin(gates, abs(b))
    left_only, right_only = left - right, right - left
    if not any((x in left_only and abs(y) in right_only) or
               (x in right_only and abs(y) in left_only) for x, y in queries):
        return None
    queries.append((a, b))
    return queries


def attempt(args, directory):
    start = time.monotonic()
    decoded = recognize(args.cnf, args.max_gates)
    if decoded is None:
        return False
    nvars, rows, gates, units, assertion = decoded
    queries = schedule(gates, units, assertion)
    if not queries:
        return False
    d = Path(directory)

    def run(command, **kwargs):
        remaining = args.seconds - (time.monotonic() - start)
        if remaining <= 0:
            raise subprocess.TimeoutExpired(command, args.seconds)
        return subprocess.run(command, timeout=remaining, **kwargs)

    with (d / 'training').open('w') as f:
        for row in rows:
            if row != (assertion,):
                print(*row, 0, file=f)
    if not args.prove_output:
        queries.pop()
    with (d / 'queries').open('w') as f:
        for i, (a, b) in enumerate(queries):
            print(a, b, 2000000 if args.prove_output and i + 1 == len(queries) else 15000, file=f)
    result = run([args.worker, d / 'training', d / 'queries', d / 'prefix', d / 'facts'])
    if result.returncode:
        return False
    facts = (d / 'facts').read_text().splitlines()
    if not facts:
        return False
    with (d / 'augmented.cnf').open('w') as f:
        print('p cnf', nvars, len(rows) + len(facts), file=f)
        for row in rows:
            print(*row, 0, file=f)
        for fact in facts:
            print(fact, file=f)
    sweep_done = time.monotonic()
    with (d / 'result').open('w') as output:
        result = run([args.wassat, d / 'augmented.cnf', '--drat', d / 'tail'], stdout=output)
    if result.returncode != 20:
        return False
    search_done = time.monotonic()
    with (d / 'prefix').open('ab') as out, (d / 'tail').open('rb') as suffix:
        shutil.copyfileobj(suffix, out)
    with (d / 'check').open('wb') as log:
        checked = run([args.checker,args.cnf, d / 'prefix'], stdout=log, stderr=subprocess.STDOUT)
    with (d / 'check').open('rb') as log:
        log.seek(max(0, log.seek(0, os.SEEK_END) - 8192))
        verified = b's VERIFIED' in log.read().splitlines()
    if checked.returncode or not verified:
        return False
    os.replace(d / 'prefix', args.drat)
    print(f'c gate miter verified original CNF, sweep {sweep_done - start:.3f}s, Wassat {search_done - sweep_done:.3f}s, composition and check {time.monotonic() - search_done:.3f}s', file=sys.stderr)
    sys.stdout.write((d / 'result').read_text())
    return True


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('cnf', type=Path)
    p.add_argument('--drat', type=Path, required=True)
    p.add_argument('--wassat', required=True)
    p.add_argument('--worker', required=True)
    p.add_argument('--checker', required=True)
    p.add_argument('--seconds', type=float, default=60, help='wall budget for the specialist including checking')
    p.add_argument('--max-gates', type=int, default=16384, help='experimental sweep admission budget')
    p.add_argument('--prove-output', action='store_true', help='also query the comparator inputs directly')
    args = p.parse_args()
    with tempfile.TemporaryDirectory(dir=args.drat.parent) as workspace:
        try:
            if attempt(args, workspace):
                return 20
        except (ValueError, subprocess.TimeoutExpired) as e:
            print(f'c gate miter declined: {e}', file=sys.stderr)
    os.execlp(args.wassat, args.wassat, str(args.cnf), '--drat', str(args.drat))


if __name__ == '__main__':
    sys.exit(main())
