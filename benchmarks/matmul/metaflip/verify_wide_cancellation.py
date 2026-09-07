#!/usr/bin/env python3
"""Independently check bounded wide-factor search endpoints and run metadata.

Exact tensor verification is not evidence of novelty, exhaustive search,
production performance, or a rank lower bound.
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

from verify_representation_portfolio import contained, parse_terms


def read_json(path):
    return json.loads(path.read_text())


def validate_run(data, source, report):
    assert data['initial_rank'] == source['initial_rank']
    assert 0 < data['rank'] <= data['initial_rank']
    if data['rank'] == data['initial_rank']:
        assert data['density'] <= source['initial_density']
    assert data['attempts'] == report['attempts_per_trial']
    assert 0 <= data['flips'] <= data['attempts']
    assert 0 <= data['pluses'] <= data['attempts']
    assert data['flips'] + data['pluses'] <= data['attempts']
    assert 0 <= data['best_at'] <= data['attempts'] and data['seconds'] > 0
    plus = data.get('plus_every', 1024)
    restart = data.get('restart_every', 250000)
    period = data.get('compress_every', 0)
    assert data['pluses'] <= data['attempts'] // plus
    assert data['restarts'] == (data['attempts'] - 1) // restart if restart else data['restarts'] == 0
    assert data.get('compression_calls', 0) == (data['attempts'] // period if period else 0)
    assert 0 <= data.get('compression_terms', 0)
    assert data['checks'] >= 3 + data['attempts'] // 100000


def verify(root, workers=2):
    root = root.resolve()
    manifest = read_json(root / 'report.json')
    assert manifest['complete'] and manifest['field'] == 'GF(2)' and not manifest['record_claim']
    for name, digest in manifest['retained_files'].items():
        assert hashlib.sha256(contained(root, name).read_bytes()).hexdigest() == digest, name
    summaries = {}
    cases = {}
    def witness(base, entry, shape, rank=None, density=None):
        path = contained(base, entry['path'])
        raw = path.read_bytes()
        assert hashlib.sha256(raw).hexdigest() == entry['sha256']
        lines = [s.strip() for s in raw.decode().splitlines() if s.strip() and not s.lstrip().startswith('#')]
        size = int(lines[0]) if lines[0].isdigit() else len(lines)
        terms = parse_terms(raw, size)
        total = sum(v.bit_count() for t in terms for v in t)
        assert rank is None or rank == size
        assert density is None or density == total
        assert tuple(entry['shape']) == tuple(shape)
        key = (tuple(shape), entry['sha256'])
        cases[key] = dict(path=str(path.relative_to(root)), shape=list(shape), rank=size, density=total, sha256=entry['sha256'])
        return terms
    passes = {}
    for name in manifest['passes']:
        base = root / name
        report = read_json(base / 'report.json')
        assert report['complete'] and not report['record_claim'] and report['field'] == 'GF(2)'
        assert len(report['rows']) == report['targets']
        assert len({tuple(r['target']) for r in report['rows']}) == report['targets']
        passes[name] = report
        attempts = flips = pluses = compression_terms = trials = gains = density_gains = 0
        for row in report['rows']:
            shape = row['target']
            witness(base, row['source'], shape, row['initial_rank'], row['initial_density'])
            assert len(row['runs']) == report['trials']
            log = [json.loads(line) for line in (base / ('x'.join(map(str, shape)) + '.log')).read_text().splitlines()]
            assert len(log) == len(row['runs'])
            for index, data in enumerate(row['runs']):
                assert data['trial'] == index
                validate_run(data, row, report)
                assert {k: data[k] for k in log[index]} == log[index]
                witness(base, data['witness'], shape, data['rank'], data['density'])
                witness(base, data['final_witness'], shape)
                for raw_key, saved_key in [('result', 'witness'), ('final', 'final_witness')]:
                    raw = contained(base / 'x'.join(map(str, shape)), data[raw_key]).read_bytes()
                    assert hashlib.sha256(raw).hexdigest() == data[saved_key]['sha256']
                attempts += data['attempts']; flips += data['flips']; pluses += data['pluses']
                compression_terms += data.get('compression_terms', 0); trials += 1
            best_rank = min(r['rank'] for r in row['runs'])
            assert row['best_rank'] == best_rank
            gains += best_rank < row['initial_rank']
            density_gains += any(r['rank'] == row['initial_rank'] and r['density'] < row['initial_density'] for r in row['runs'])
        summaries[name] = dict(targets=report['targets'], trials=trials, attempts=attempts, flips=flips,
            pluses=pluses, compression_terms=compression_terms, rank_gains=gains, density_gain_targets=density_gains)
    if {'control', 'compressed'} <= passes.keys():
        a, b = passes['control'], passes['compressed']
        assert a['binary_sha256'] == b['binary_sha256']
        for key in ('attempts_per_trial', 'trials', 'rank_debt', 'sampler', 'targets'):
            assert a[key] == b[key]
        for left, right in zip(a['rows'], b['rows']):
            for key in ('target', 'initial_rank', 'initial_density', 'seed', 'source'):
                assert left[key] == right[key]
            for x, y in zip(left['runs'], right['runs']):
                assert x['plus_every'] == y['plus_every'] and x['restart_every'] == y['restart_every']
                assert x['compress_every'] == 0 and y['compress_every'] == 8192
    checker = root / 'tools/verify_block_composition_records.py'
    spec = importlib.util.spec_from_file_location('wide_tensor_checker', checker)
    tensor = importlib.util.module_from_spec(spec); sys.modules[spec.name] = tensor; spec.loader.exec_module(tensor)
    records = []
    with tempfile.TemporaryDirectory(prefix='metaflip-wide-check-') as temporary:
        temporary = Path(temporary)
        for index, case in enumerate(cases.values()):
            raw = contained(root, case['path']).read_bytes()
            terms = parse_terms(raw, case['rank'])
            body = ''.join('R ' + ' '.join(map(str, t)) + '\n' for t in terms).encode()
            name = f'{index}.txt'; (temporary / name).write_bytes(body)
            records.append((temporary, tensor.Record('x'.join(map(str, case['shape'])), tuple(case['shape']),
                case['rank'], name, hashlib.sha256(body).hexdigest())))
        if workers == 1:
            results = list(map(tensor._verify_one, records))
        else:
            with ProcessPoolExecutor(max_workers=workers, mp_context=multiprocessing.get_context('fork')) as pool:
                results = list(pool.map(tensor._verify_one, records))
    return dict(schema=1, complete=True, field='GF(2)', record_claim=False, cases=len(results),
        terms=sum(r.terms for r in results), pair_xors=sum(r.pair_xors for r in results),
        passes=summaries, results=[asdict(r) for r in results])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--workers', type=int, choices=range(1, 5), default=2)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args(); result = verify(args.root, args.workers)
    if args.report: args.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'results'}))
