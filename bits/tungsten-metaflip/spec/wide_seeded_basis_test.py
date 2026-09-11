#!/usr/bin/env python3
"""Seeded native matrix bases against coordinate-relabelled row equations."""
from collections import Counter, defaultdict
from hashlib import sha256
from itertools import product
from pathlib import Path
import argparse
import json
import random
import subprocess
import tempfile

from wide_matrix_cleanup_parity_test import blob, read_blob, same_tensor
from packed_composition_parity_test import bits, exact, naive
from verify_cofactor_mergers import matrix_factors


def column_order(width, fixed, seed):
    assert width in range(32, 1025, 32) and 0 <= seed <= 0xffffffff
    state = seed ^ 2654435769
    for shift in range(0, width, 32):
        state = ((state ^ ((fixed >> shift) & 0xffffffff)) * 16777619) % (1 << 32)
    order = list(range(width))
    for i in range(width-1, 0, -1):
        state = (1664525 * state + 1013904223) % (1 << 32)
        j = state % (i+1)
        order[i], order[j] = order[j], order[i]
    assert sorted(order) == list(range(width))
    return order


def seeded_refactor(shape, terms, axis, seed):
    # Select basis columns by relabelling the right coordinate, using the
    # existing independent row-equation solver, then undoing that relabelling.
    # This does not reproduce the native incremental column elimination.
    width = 32*((max(shape[0]*shape[1], shape[1]*shape[2], shape[0]*shape[2])+31)//32)
    groups = defaultdict(list)
    for term in terms:
        groups[term[axis]].append(tuple(term))
    other = [i for i in range(3) if i != axis]
    result = Counter()
    for fixed, group in groups.items():
        if len(group) < 2:
            result.update(group)
            continue
        order = column_order(width, fixed, seed)
        inverse = {old: new for new, old in enumerate(order)}
        pairs = [(t[other[0]], sum(1 << inverse[j] for j in bits(t[other[1]]))) for t in group]
        factors = matrix_factors(pairs, max_bits=width)
        assert len(factors) <= len(group)
        for left, right in factors:
            row = [0, 0, 0]
            row[axis], row[other[0]] = fixed, left
            row[other[1]] = sum(1 << order[j] for j in bits(right))
            result[tuple(row)] += 1
    return sorted(t for t, count in result.items() if count % 2)


def check(binary, legacy=None, report=None):
    binary = Path(binary).resolve()
    r = subprocess.run([str(binary)], capture_output=True, text=True, timeout=60, check=True)
    assert 'PASS wide matrix' in r.stdout
    rng = random.Random(202609101)
    counts = dict(runs=0, limited=0, neutral=0, full_tensors=0, legacy_comparisons=0)
    shapes = [(1,1,x) for x in (31,32,33,63,64,65,127,256,511,756,1023,1024)]
    shapes += [(3,5,7), (8,8,8), (2,17,3), (1,2,511)]
    seeds = (0, 1, 0x12345678, 0xffffffff)
    with tempfile.TemporaryDirectory(prefix='metaflip-seeded-basis-') as temp:
        root = Path(temp); source = root/'in.tensor'; target = root/'out.tensor'

        def run(shape, terms, axis, seed, budget):
            raw = blob(shape, terms); source.write_bytes(raw)
            args = ['--basis-seeded', str(source), str(target), str(budget), str(axis), str(seed)]
            r = subprocess.run([str(binary), *args], capture_output=True, text=True, timeout=30, check=True)
            fields = r.stdout.split(); assert fields[0] == 'WIDE_SEEDED' and len(fields) == 8
            before, after, work, limited, axes, groups, saved = map(int, fields[1:])
            dims, result = read_blob(target.read_bytes())
            assert dims == shape and source.read_bytes() == raw
            assert before == len(terms) and after == len(result) <= before
            assert limited in (0,1) and axes == 1-limited and 0 <= groups <= saved <= before-after
            assert budget == 0 or work <= budget
            same_tensor(terms, result)
            if not limited:
                assert result == seeded_refactor(shape, terms, axis, seed), (shape,axis,seed,budget)
            counts['runs'] += 1; counts['limited'] += limited
            counts['neutral'] += after == before and result != terms
            return result

        for trial, shape in enumerate(shapes):
            widths = (shape[0]*shape[1], shape[1]*shape[2], shape[0]*shape[2])
            palettes = [[sum(1 << b for b in rng.sample(range(w), min(w,rng.randrange(1,6)))) for _ in range(7)] for w in widths]
            terms = sorted({tuple(rng.choice(p) for p in palettes) for _ in range(19+trial)})
            for axis, seed, budget in product(range(3), seeds, (0,1,3000,50000)):
                run(shape, terms, axis, seed, budget)
            if legacy is not None:
                source.write_bytes(blob(shape, terms))
                for mode, extra in [('--clean',[]), *[('--basis',[str(a),str(d)]) for a,d in product(range(3),range(2))]]:
                    args = [mode,str(source),str(target),'20000000',*extra]
                    old = subprocess.run([str(legacy),*args], capture_output=True,text=True,timeout=30,check=True)
                    before = target.read_bytes()
                    new = subprocess.run([str(binary),*args], capture_output=True,text=True,timeout=30,check=True)
                    assert new.stdout == old.stdout and target.read_bytes() == before
                    counts['legacy_comparisons'] += 1

        for shape in ((2,2,2), (3,3,3), (4,7,4), (5,5,5), (1,1,65)):
            terms = naive(shape)
            if shape == (1,1,65):
                terms = [(1,3,1),(1,2,3)] + [(1,1<<i,1<<i) for i in range(2,65)]
            for axis,seed in product(range(3), seeds):
                result = run(shape, sorted(terms), axis, seed, 20000000)
                exact(shape, result); counts['full_tensors'] += 1

        # Three dependent columns offer a third basis unseen by both legacy
        # monotone orders. Do not just rename the old two-mode family.
        shape=(2,2,2); terms=[(1,2,3),(1,4,6)]
        endpoints={tuple(run(shape,terms,0,seed,0)) for seed in range(16)}
        assert len(endpoints) >= 3
        counts['distinct_dependent_column_bases'] = len(endpoints)
        source.write_bytes(blob((2,2,2),naive((2,2,2))))
        target.unlink()
        for axis,seed,budget in ((3,0,1),(0,-1,1),(0,4294967296,1),(0,0,1000000001)):
            r = subprocess.run([str(binary),'--basis-seeded',str(source),str(target),str(budget),str(axis),str(seed)],
                               capture_output=True,text=True,timeout=10)
            assert r.returncode != 0 and not target.exists()
    assert counts['limited'] > 0 and counts['neutral'] > 0
    out=dict(complete=True,record_claim=False,counts=counts,binary_sha256=sha256(binary.read_bytes()).hexdigest())
    if report:
        assert not report.exists(); report.write_text(json.dumps(out,indent=2)+'\n')
    print(json.dumps(out),flush=True)


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('binary',type=Path); p.add_argument('--legacy',type=Path); p.add_argument('--report',type=Path)
    a=p.parse_args(); check(a.binary,a.legacy,a.report)
