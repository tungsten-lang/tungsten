#!/usr/bin/env python3
"""Independently replay a finite block/Kronecker grid and its admitted tensors.

Catalog ranks are comparison data, never tensor witnesses or a novelty oracle.
The DP below does not import the Ruby planner or any native fleet code.
"""
import argparse
import concurrent.futures
import dataclasses
from functools import lru_cache
import hashlib
import importlib.util
import itertools
import json
import math
import multiprocessing
from pathlib import Path
import sys
import tempfile


def solver(seeds, expressions=None):
    # Optional reported substitution templates are for reference screening.
    # The certificate/grid verifier calls this with no supplemental edges.
    expressions = expressions or {}
    for target, alternatives in expressions.items():
        assert len(target) == 3 and tuple(sorted(target)) == target and all(type(n) is int and n > 0 for n in target)
        for terms in alternatives:
            assert terms
            for count, leaf in terms:
                assert type(count) is int and count > 0 and len(leaf) == 3
                assert tuple(sorted(leaf)) == leaf and all(type(n) is int and n > 0 for n in leaf)
                assert math.prod(leaf) < math.prod(target), 'non-decreasing reference dependency'
    @lru_cache(None)
    def rank(shape):
        best = min(math.prod(shape), seeds.get(shape, math.prod(shape)))
        for terms in expressions.get(shape, ()):
            best = min(best, sum(count * rank(leaf) for count, leaf in terms))
        if 1 in shape:
            return best
        for axis, extent in enumerate(shape):
            # Deliberately enumerate both halves, unlike the Ruby planner.
            for cut in range(1, extent):
                left, right = list(shape), list(shape)
                left[axis], right[axis] = cut, extent - cut
                best = min(best, rank(tuple(sorted(left))) + rank(tuple(sorted(right))))
        choices = [[d for d in range(1, n + 1) if n % d == 0] for n in shape]
        for left in itertools.product(*choices):
            right = tuple(n // d for n, d in zip(shape, left))
            if left == (1, 1, 1) or right == (1, 1, 1):
                continue
            best = min(best, rank(tuple(sorted(left))) * rank(tuple(sorted(right))))
        return best
    return rank


def catalog_minima(index):
    result = {}
    for e in index['schemes']:
        if (e.get('verified') is not True or 'F2' not in e.get('fields', []) or
                'F2' in e.get('fields_not', []) or e.get('commutative') or
                e.get('scheme_type') == 'non_bilinear'):
            continue
        key = tuple(sorted(e['format']))
        result[key] = min(result.get(key, e['rank']), e['rank'])
    return result


def safe(root, relative):
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError('snapshot outside report root')
    return path


def verify(root, admitted, verifier_path, workers=2):
    raw_report = (root / 'report.json').read_bytes()
    report = json.loads(raw_report)
    assert report['complete'] and report['field'] == 'GF(2)' and not report['record_claim']
    assert 1 <= report['minimum'] <= report['maximum'] <= 32
    tensors, bases = {}, {'base': {}, 'new': {}}

    def add(base, entry, expected_rank=None):
        path = safe(base, entry['path'])
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        assert digest == entry['sha256'], path
        shape = tuple(entry['shape'])
        assert len(shape) == 3 and all(type(n) is int and 1 <= n <= 32 for n in shape)
        lines = [l.strip() for l in raw.decode('ascii').splitlines() if l.strip() and not l.startswith('#')]
        rank = int(lines.pop(0))
        assert rank == len(lines) and (expected_rank is None or rank == expected_rank)
        key = (shape, digest)
        tensors[key] = dict(path=str(path), shape=shape, rank=rank, sha256=digest, lines=lines)
        return shape, rank

    for row in report['basis']:
        shape, rank = add(root, row['snapshot'], row['rank'])
        by_shape = bases[row['kind']]
        key = tuple(sorted(shape))
        by_shape[key] = min(by_shape.get(key, rank), rank)
    merged = dict(bases['base'])
    for key, rank in bases['new'].items():
        merged[key] = min(merged.get(key, rank), rank)
    known, augmented = solver(bases['base']), solver(merged)
    expected = list(itertools.combinations_with_replacement(range(report['minimum'], report['maximum'] + 1), 3))
    assert [tuple(r['shape']) for r in report['rows']] == expected
    catalog = catalog_minima(json.loads((root / 'catalog-index.json').read_text()))
    improved = {}

    def recipe(base, relative, shape, rank):
        path = safe(base, relative)
        data = json.loads(path.read_text())
        assert data['field'] == 'GF(2)' and data['exact_rank'] == rank
        assert tuple(data['result']['shape']) == shape
        for entry in [data['parent'], data['result']] + [g['leaf'] for g in data['groups']]:
            add(path.parent, entry, rank if entry == data['result'] else None)

    for row in report['rows']:
        shape = tuple(row['shape'])
        before, after = known(shape), augmented(shape)
        assert (row['known_rank'], row['augmented_rank'], row['gain']) == (before, after, before - after)
        assert after <= before
        ref = catalog.get(shape)
        assert row['catalog_minimum'] == ref
        assert row['below_catalog'] == (None if ref is None else after < ref)
        if before > after:
            improved[shape] = row
        if row.get('recipe'):
            recipe(root, row['recipe'], shape, after)
    assert report['summary']['targets'] == len(expected)
    assert report['summary']['improved_prices'] == len(improved)
    assert report['summary']['improved_with_catalog'] == sum(r['catalog_minimum'] is not None for r in improved.values())
    assert report['summary']['improved_below_catalog'] == sum(bool(r['below_catalog']) for r in improved.values())
    extra = json.loads((admitted / 'report.json').read_text())
    assert extra['complete'] and extra['field'] == 'GF(2)' and not extra['record_claim']
    assert extra['source_report_sha256'] == hashlib.sha256(raw_report).hexdigest()
    assert len(extra['rows']) == len(improved) and {tuple(r['shape']) for r in extra['rows']} == set(improved)
    for row in extra['rows']:
        shape = tuple(row['shape'])
        assert row['rank'] == improved[shape]['augmented_rank'] and row['gain'] == improved[shape]['gain']
        recipe(admitted, row['recipe'], shape, row['rank'])

    spec = importlib.util.spec_from_file_location('recursive_independent_tensor', verifier_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    cases = list(tensors.values())
    with tempfile.TemporaryDirectory(prefix='metaflip-recursive-tensors-') as directory:
        temporary = Path(directory)
        tasks = []
        for i, case in enumerate(cases):
            body = ''.join((l if l.startswith('R ') else 'R ' + l) + '\n' for l in case['lines']).encode('ascii')
            name = f'{i}.txt'
            (temporary / name).write_bytes(body)
            record = module.Record('x'.join(map(str, case['shape'])), case['shape'], case['rank'], name,
                                   hashlib.sha256(body).hexdigest())
            tasks.append((temporary, record))
        with concurrent.futures.ProcessPoolExecutor(max_workers=workers, mp_context=multiprocessing.get_context('fork')) as pool:
            results = list(pool.map(module._verify_one, tasks))
    return dict(schema=1, field='GF(2)', record_claim=False, dp_shapes=len(expected),
                improved_shapes=len(improved), tensor_cases=len(results),
                terms=sum(r.terms for r in results), pair_xors=sum(r.pair_xors for r in results),
                cases=[dict(path=c['path'], shape=c['shape'], rank=c['rank'], sha256=c['sha256'],
                            independent=dataclasses.asdict(r)) for c, r in zip(cases, results)])


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--admitted', type=Path, required=True)
    p.add_argument('--verifier', type=Path, default=Path(__file__).with_name('verify_block_composition_records.py'))
    p.add_argument('--workers', type=int, choices=range(1, 5), default=2)
    p.add_argument('--report', type=Path)
    args = p.parse_args()
    result = verify(args.root, args.admitted, args.verifier, args.workers)
    if args.report:
        args.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'cases'}))
