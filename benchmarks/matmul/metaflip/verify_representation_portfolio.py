#!/usr/bin/env python3
"""Check retained representation-walk evidence and every complete GF(2) tensor.

This is an independent tensor check, not a novelty or neighborhood-exhaustion
oracle. Source and timing evidence are pinned separately from tensor identity.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ProcessPoolExecutor
from dataclasses import asdict
import hashlib
import importlib.util
import json
import multiprocessing
from pathlib import Path
import sys
import tempfile


def read_json(path):
    return json.loads(path.read_text())


def contained(root, name):
    path = (root / name).resolve()
    if not path.is_relative_to(root.resolve()):
        raise ValueError(f'path escapes artifact: {name}')
    return path


def check_walk(report):
    assert report['complete'] and not report['record_claim'] and report['field'] == 'GF(2)'
    assert len(report['rows']) == report['targets']
    assert len({tuple(r['target']) for r in report['rows']}) == report['targets']
    for row in report['rows']:
        scores = [(row['initial_rank'], row['initial_density'])]
        scores += [(s['rank'], s['density']) for s in row['history']]
        assert all(b < a for a, b in zip(scores, scores[1:]))
        assert scores[-1] == (row['rank'], row['density'])
        assert row['history_replayed'] and 1 <= row['rounds'] <= row['round_limit']
        if 'verification' in row:
            expected = row['checks'] if row['verification'] == 'all' else len(row['history'])
            assert row['verification'] in ('all', 'winner')
            assert row['verified_neighbors'] == expected
        assert row.get('pair_checks', 0) <= row['checks']
        for step in row['history']:
            if step['kind'] == 'kernel_pair':
                parts = step['components']
                assert len(parts) == 2 and len({p['axis'] for p in parts}) == 2
                assert all(p['kind'] == 'kernel' for p in parts)
                assert step['word'] == [move for p in parts for move in p['word']]


def parse_terms(raw, rank):
    lines = [s.strip() for s in raw.decode('ascii').splitlines()
             if s.strip() and not s.lstrip().startswith('#')]
    if lines and lines[0].isdigit():
        assert int(lines.pop(0)) == rank
    terms = [tuple(map(int, s.removeprefix('R ').split())) for s in lines]
    assert len(terms) == rank and all(len(t) == 3 for t in terms)
    return terms


def identity(shape, terms):
    body = str(len(terms)) + '\n' + ''.join(' '.join(map(str, t)) + '\n' for t in sorted(terms))
    return hashlib.sha256(('x'.join(map(str, shape)) + '\n' + body).encode()).hexdigest()


def apply_word(shape, terms, word):
    # Expand source bits, unlike the Ruby row/column loop and factor caches.
    edges = ((0, 1), (1, 2), (0, 2))
    result = [list(t) for t in terms]
    for axis, dst, src in word:
        assert 0 <= axis < 3 and 0 <= dst < shape[axis] and 0 <= src < shape[axis] and dst != src
        affected = [index for index, edge in enumerate(edges) if axis in edge]
        for dual, edge in enumerate(affected):
            row, col = edges[edge]
            destination, source = (src, dst) if dual else (dst, src)
            for term in result:
                old = term[edge]
                bits = old
                while bits:
                    low = bits & -bits
                    i, j = divmod(low.bit_length() - 1, shape[col])
                    bits ^= low
                    if (i if axis == row else j) == source:
                        position = destination * shape[col] + j if axis == row else i * shape[col] + destination
                        term[edge] ^= 1 << position
    return [tuple(t) for t in result]


def check_histories(root, stages, benchmark, cases):
    saved = read_json(root / 'history-replay.json')
    groups = {}
    for entry in saved:
        groups.setdefault((entry['stage'], tuple(entry['target'])), []).append(entry)
    case_ids = {(tuple(c['shape']), c['sha256']) for c in cases}

    def load(base, entry):
        raw = contained(base, entry['path']).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == entry['sha256']
        lines = [s.strip() for s in raw.decode('ascii').splitlines()
                 if s.strip() and not s.lstrip().startswith('#')]
        rank = int(lines[0]) if lines[0].isdigit() else len(lines)
        return tuple(entry['shape']), parse_terms(raw, rank)

    jobs = [(name, row, row['history'], root / name / row['initial_recipe'], root / name / row['recipe'])
            for name, data in stages.items() for row in data['rows']]
    jobs += [('benchmark', row, row['signature']['history'],
              root / 'baseline/initial' / ('x'.join(map(str, row['target'])) + '.recipe.json'),
              root / 'benchmark' / row['recipe']) for row in benchmark['rows']]
    total = 0
    for name, row, history, initial_path, final_path in jobs:
        initial = read_json(initial_path)
        current = [load(initial_path.parent, e) if e else None for e in initial['leaves']]
        records = groups.pop((name, tuple(row['target'])), [])
        assert len(records) == len(history)
        for index, (step, record) in enumerate(zip(history, records)):
            assert record['index'] == index and record['action'] == step
            slot = step['slot']
            shape, terms = current[slot]
            assert identity(shape, terms) == step['from']
            changed = apply_word(shape, terms, step['word'])
            assert identity(shape, changed) == step['to']
            assert load(root, record['leaf']) == (shape, changed)
            state_shape, state_terms = load(root, record['snapshot'])
            assert state_shape == tuple(map(sum, initial['allocation']))
            assert (len(state_terms), sum(v.bit_count() for t in state_terms for v in t)) == (step['rank'], step['density'])
            for kind in ('leaf', 'snapshot'):
                entry = record[kind]
                assert (tuple(entry['shape']), entry['sha256']) in case_ids
            current[slot] = (shape, changed)
            total += 1
        final = read_json(final_path)
        finish = [load(final_path.parent, e) if e else None for e in final['leaves']]
        assert current == finish
    assert not groups
    return total


def verify(root, workers=2):
    root = root.resolve()
    report = read_json(root / 'report.json')
    assert report['field'] == 'GF(2)' and not report['record_claim']
    for name, digest in report['retained_files'].items():
        assert hashlib.sha256(contained(root, name).read_bytes()).hexdigest() == digest, name
    stages = {name: read_json(root / name / 'report.json') for name in report['walks']}
    for name, data in stages.items():
        check_walk(data)
        for row in data['rows']:
            recipe = read_json(contained(root / name, row['recipe']))
            assert recipe['exact_rank'] == row['rank']
            assert recipe['result']['sha256'] == row['result_sha256']
    keys = ('target', 'rank', 'density', 'checks', 'history', 'rounds', 'settled', 'result_sha256')
    all_rows = stages['baseline']['rows']
    fast_rows = stages['screened']['rows']
    assert len(all_rows) == len(fast_rows) == 28
    for a, b in zip(all_rows, fast_rows):
        assert {k: a[k] for k in keys} == {k: b[k] for k in keys}
    bench = read_json(root / 'benchmark/report.json')
    assert bench['complete'] and len(bench['rows']) == 6
    ratios = []
    for row in bench['rows']:
        runs = row['timings']
        assert [r['mode'] for r in runs] == ['all', 'winner', 'winner', 'all']
        assert all(r['checks'] == row['signature']['checks'] for r in runs)
        for run in runs:
            expected = run['checks'] if run['mode'] == 'all' else len(row['signature']['history'])
            assert run['verified_neighbors'] == expected
        means = {mode: sum(r['seconds'] for r in runs if r['mode'] == mode) / 2
                 for mode in ('all', 'winner')}
        assert means == row['means']
        assert row['observed_ratio'] == means['all'] / means['winner']
        ratios.append(row['observed_ratio'])
    histories = check_histories(root, stages, bench, report['cases'])
    assert histories == report['replayed_intermediates']
    checker = root / 'tools/verify_block_composition_records.py'
    spec = importlib.util.spec_from_file_location('retained_tensor_checker', checker)
    tensor = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = tensor
    spec.loader.exec_module(tensor)
    records = []
    identities = set()
    with tempfile.TemporaryDirectory(prefix='metaflip-representation-check-') as temporary:
        temporary = Path(temporary)
        for index, case in enumerate(report['cases']):
            raw = contained(root, case['path']).read_bytes()
            assert hashlib.sha256(raw).hexdigest() == case['sha256']
            terms = parse_terms(raw, case['rank'])
            assert sum(v.bit_count() for t in terms for v in t) == case['density']
            identity = (tuple(case['shape']), case['sha256'])
            assert identity not in identities
            identities.add(identity)
            body = ''.join('R ' + ' '.join(map(str, t)) + '\n' for t in terms).encode()
            name = f'{index}.txt'
            (temporary / name).write_bytes(body)
            records.append((temporary, tensor.Record('x'.join(map(str, case['shape'])),
                tuple(case['shape']), case['rank'], name, hashlib.sha256(body).hexdigest())))
        if workers == 1:
            results = list(map(tensor._verify_one, records))
        else:
            with ProcessPoolExecutor(max_workers=workers, mp_context=multiprocessing.get_context('fork')) as pool:
                results = list(pool.map(tensor._verify_one, records))
    return dict(schema=1, field='GF(2)', record_claim=False, cases=len(results),
        terms=sum(r.terms for r in results), pair_xors=sum(r.pair_xors for r in results),
        matched_targets=len(all_rows), matched_checks=sum(r['checks'] for r in all_rows),
        independent_history_steps=histories,
        benchmark_ratios=ratios, walks={name: dict(targets=len(data['rows']),
            checks=sum(r['checks'] for r in data['rows']),
            pair_checks=sum(r.get('pair_checks', 0) for r in data['rows']),
            rank_gains=sum(r['rank'] < r['initial_rank'] for r in data['rows']),
            density_gains=sum(r['density'] < r['initial_density'] for r in data['rows']))
            for name, data in stages.items()}, results=[asdict(r) for r in results])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--workers', type=int, choices=range(1, 5), default=2)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = verify(args.root, args.workers)
    if args.report:
        args.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'results'}))
