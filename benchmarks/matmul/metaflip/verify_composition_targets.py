#!/usr/bin/env python3
"""Replay targeted block/Kronecker compositions, including their full ancestry.

Exact GF(2) witnesses and finite-library improvements are not novelty claims.
This checker is independent of the Ruby planner and constructor.
"""
import argparse
from concurrent.futures import ProcessPoolExecutor
from dataclasses import asdict
import hashlib
from itertools import permutations, product
import json
import math
import multiprocessing
from pathlib import Path
import tempfile

import verify_block_composition_records as tensor
from verify_cofactor_mergers import orient
from verify_recursive_portfolio import safe, solver
from verify_representation_portfolio import identity, parse_terms

EDGES = ((0, 1), (1, 2), (0, 2))


def positions(word):
    while word:
        bit = word & -word
        yield bit.bit_length() - 1
        word ^= bit


def dimensions(shape):
    assert len(shape) == 3 and all(type(d) is int and 1 <= d <= 64 for d in shape)
    return tuple(shape)


def naive(shape):
    n, m, p = shape
    return [(1 << (i*m+j), 1 << (j*p+k), 1 << (i*p+k))
            for i, j, k in product(range(n), range(m), range(p))]


def block(shape, terms, target, offsets):
    assert all(0 <= o and d+o <= t for d, o, t in zip(shape, offsets, target))
    return [tuple(sum(1 << ((bit//shape[c]+offsets[r])*target[c]+bit % shape[c]+offsets[c])
                      for bit in positions(word))
                  for word, (r, c) in zip(term, EDGES)) for term in terms]


def kronecker(left_shape, left, right_shape, right):
    # Separate coordinate substitution, not the producer's cached block maps.
    transforms = []
    for r, c in EDGES:
        transforms.append(lambda a, b, r=r, c=c: sum(
            1 << ((i//left_shape[c]*right_shape[r]+j//right_shape[c]) *
                  (left_shape[c]*right_shape[c])+i % left_shape[c]*right_shape[c]+j % right_shape[c])
            for i in positions(a) for j in positions(b)))
    return [tuple(f(a, b) for f, a, b in zip(transforms, l, r)) for l in left for r in right]


def replay(plan, seeds, cost, materialize=True):
    shape = dimensions(plan['shape'])
    key = tuple(sorted(shape))
    assert dimensions(plan['canonical_shape']) == key
    rank = plan['rank']
    assert type(rank) is int and rank == cost(key)
    kind = plan['kind']
    if kind == 'seed':
        source_shape, raw_hash, terms = seeds[plan['source_id']]
        assert list(source_shape) == plan['source_shape'] and raw_hash == plan['source_sha256']
        assert sorted(source_shape) == list(key) and len(terms) == rank
        result = orient(source_shape, terms, key) if materialize else None
    elif kind == 'naive':
        assert rank == math.prod(key)
        result = naive(key) if materialize else None
    else:
        assert kind in ('split', 'product')
        a, b = dimensions(plan['left']['shape']), dimensions(plan['right']['shape'])
        left = replay(plan['left'], seeds, cost, materialize)
        right = replay(plan['right'], seeds, cost, materialize)
        if kind == 'split':
            axis = plan['axis']
            assert type(axis) is int and axis in range(3)
            assert all((a[i]+b[i] == key[i]) if i == axis else (a[i] == b[i] == key[i]) for i in range(3))
            assert rank == plan['left']['rank']+plan['right']['rank']
            offsets = [a[i] if i == axis else 0 for i in range(3)]
            result = block(a, left, key, [0, 0, 0])+block(b, right, key, offsets) if materialize else None
        else:
            assert tuple(x*y for x, y in zip(a, b)) == key
            assert rank == plan['left']['rank']*plan['right']['rank']
            result = kronecker(a, left, b, right) if materialize else None
    if not materialize:
        return None
    assert len(result) == rank
    return orient(key, result, shape)


def verify(root, workers=2):
    root = root.resolve()
    raw_report = (root/'report.json').read_bytes()
    report = json.loads(raw_report)
    assert report['complete'] and report['field'] == 'GF(2)' and report['record_claim'] is False
    assert report['redistribution_cleared'] is False
    cases, seeds, ranks = {}, {'base': {}, 'new': {}}, {'base': {}, 'new': {}}

    def load(entry, expected_rank):
        shape = dimensions(entry['shape'])
        path = safe(root, entry['path'])
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        assert digest == entry['sha256']
        terms = parse_terms(raw, expected_rank)
        assert all(len(t) == 3 and all(type(v) is int and 0 < v < 1 << (shape[r]*shape[c])
                   for v, (r, c) in zip(t, EDGES)) for t in terms)
        cases[(shape, digest)] = (str(path.relative_to(root)), terms)
        return shape, digest, terms

    for row in report['basis']:
        kind = row['kind']
        assert kind in ranks
        shape, digest, terms = load(row['snapshot'], row['rank'])
        key = tuple(sorted(shape))
        ranks[kind][key] = min(ranks[kind].get(key, len(terms)), len(terms))
        seeds[kind][identity(shape, terms)] = shape, digest, terms
    merged = dict(ranks['base'])
    for shape, rank in ranks['new'].items():
        merged[shape] = min(merged.get(shape, rank), rank)
    old, new = solver(ranks['base']), solver(merged)
    all_seeds = seeds['base'] | seeds['new']

    screen = json.loads((root/'screen.json').read_text())
    assert screen['complete'] and screen['field'] == 'GF(2)' and screen['record_claim'] is False
    expected = {}
    for parent, rank in ranks['new'].items():
        for partner in [(2, 2, 2), (2, 2, 3), (2, 3, 3), (3, 3, 3)]:
            for orientation in set(permutations(partner)):
                shape = tuple(sorted(a*b for a, b in zip(parent, orientation)))
                if max(shape) <= 64:
                    value = rank*ranks['base'][partner]
                    expected[shape] = min(expected.get(shape, value), value)
    assert [tuple(r['shape']) for r in screen['rows']] == sorted(expected)
    selected = []
    direct_improvements = 0
    for row in screen['rows']:
        shape = dimensions(row['shape'])
        before, after = old(shape), new(shape)
        assert (row['baseline_rank'], row['augmented_rank'], row['gain']) == (before, after, before-after)
        assert row['product_rank'] == expected[shape]
        assert row['direct_product_gain'] == before-expected[shape]
        assert after <= min(before, expected[shape])
        parent, partner = tuple(row['parent_shape']), tuple(row['partner_shape'])
        assert row['parent_rank'] == ranks['new'][parent] and row['partner_rank'] == ranks['base'][partner]
        assert sorted(row['orientation']) == sorted(partner)
        assert sorted(a*b for a, b in zip(parent, row['orientation'])) == list(shape)
        assert row['product_rank'] == row['parent_rank']*row['partner_rank']
        direct_improvements += before > expected[shape]
        if before > after:
            selected.append(shape)
    assert screen['targets'] == report['screen_targets'] == len(expected)
    assert screen['improved'] == len(selected)
    assert screen['direct_product_improved'] == direct_improvements
    assert [tuple(s) for s in report['targets']] == selected
    assert [tuple(r['shape']) for r in report['rows']] == selected
    for row in report['rows']:
        shape = dimensions(row['shape'])
        before, after = old(shape), new(shape)
        assert (row['known_rank'], row['augmented_rank'], row['gain']) == (before, after, before-after)
        assert row['known_plan']['shape'] == row['shape'] == row['augmented_plan']['shape']
        replay(row['known_plan'], seeds['base'], old, False)
        expanded = replay(row['augmented_plan'], all_seeds, new)
        actual_shape, _, actual = load(row['snapshot'], after)
        assert actual_shape == shape and sorted(expanded) == sorted(actual), 'ancestry mismatch'
        print(json.dumps(dict(ancestry_replayed=shape, rank=after)), flush=True)
    with tempfile.TemporaryDirectory(prefix='metaflip-targeted-verify-') as directory:
        tmp = Path(directory)
        jobs = []
        for i, ((shape, _), (_, terms)) in enumerate(cases.items()):
            body = ''.join('R '+' '.join(map(str, t))+'\n' for t in terms).encode()
            name = f'{i}.txt'
            (tmp/name).write_bytes(body)
            jobs.append((tmp, tensor.Record('x'.join(map(str, shape)), shape, len(terms), name,
                                           hashlib.sha256(body).hexdigest())))
        if workers == 1:
            checks = list(map(tensor._verify_one, jobs))
        else:
            with ProcessPoolExecutor(max_workers=workers, mp_context=multiprocessing.get_context('fork')) as pool:
                checks = list(pool.map(tensor._verify_one, jobs))
    return dict(schema=1, complete=True, field='GF(2)', record_claim=False,
                source_report_sha256=hashlib.sha256(raw_report).hexdigest(),
                screen_targets=len(expected), improved_targets=len(selected),
                direct_product_improvements=direct_improvements, ancestry_replays=len(selected),
                tensors=len(checks), terms=sum(c.terms for c in checks), pair_xors=sum(c.pair_xors for c in checks),
                cases=[dict(path=p, independent=asdict(c)) for (p, _), c in zip(cases.values(), checks)])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--workers', type=int, choices=range(1, 5), default=2)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = verify(args.root, args.workers)
    if args.report:
        args.report.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'cases'}))
