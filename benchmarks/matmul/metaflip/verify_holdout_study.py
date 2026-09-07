#!/usr/bin/env python3
"""Replay full parent/product tensors and construction maps in a holdout study.

This imports no Ruby composer or native walker. Search optimality, elapsed
time comparisons, and global novelty are deliberately outside its scope.
"""
import argparse
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
from dataclasses import asdict
import hashlib
import json
import multiprocessing
from pathlib import Path
import tempfile

import verify_block_composition_records as tensor
from verify_bud_renewal import expand_group
from verify_representation_portfolio import contained, parse_terms


def verify(root, workers=2):
    root = root.resolve()
    read = lambda path: json.loads(path.read_text())
    summary = read(root/'report.json')
    assert summary['complete'] and summary['field'] == 'GF(2)' and not summary['record_claim']
    tensors, pins = {}, {}

    def load(path, shape, digest):
        shape = tuple(shape)
        assert len(shape) == 3 and all(type(d) is int and 1 <= d <= 32 for d in shape)
        raw = path.read_bytes()
        assert hashlib.sha256(raw).hexdigest() == digest, path
        pins[str(path.relative_to(root))] = digest
        terms = parse_terms(raw, int(raw.splitlines()[0]))
        body = ''.join('R '+' '.join(map(str, t))+'\n' for t in terms).encode()
        tensors[shape, hashlib.sha256(body).hexdigest()] = body
        return terms

    def snapshot(base, entry):
        return load(contained(base, entry['path']), entry['shape'], entry['sha256'])

    paths = [entry['report'] for row in summary['rows'] for entry in row['arms']]
    if 'grid_followup' in summary:
        paths.append(summary['grid_followup']['report'])
    attempts, products, ends = 0, 0, 0
    for relative in paths:
        path = contained(root, relative)
        study = read(path)
        assert study['field'] == 'GF(2)' and not study['record_claim']
        assert study['binary_sha256'] == summary['binary_sha256']
        source = snapshot(path.parent, study['parent'])
        shape = study['parent']['shape']
        held = study.get('holdout')
        if held:
            raw = contained(path.parent, held['path']).read_bytes()
            assert hashlib.sha256(raw).hexdigest() == held['sha256']
            terms = parse_terms(raw, len(held['terms']))
            assert terms == [tuple(t) for t in held['terms']]
            assert len(set(terms)) == len(terms) < len(source) and all(t in source for t in terms)
        options = study['options']
        assert [arm['mode'] for arm in study['arms']] == ['walk', 'greedy', 'anneal']
        for arm in study['arms']:
            expected = options['trials'] * options['chunks'] * options['steps']
            assert int(arm['totals']['attempted']) == expected == summary['attempts_per_policy']
            assert int(arm['totals']['held_terms']) == (len(held['terms']) if held else 0)
            assert len(arm['trials']) == options['trials']
            attempts += expected
            for index, trial in enumerate(arm['trials']):
                assert trial['trial'] == index
                directory = path.parent/arm['mode']
                parent = load(directory/f'trial-{index}.txt', shape, trial['parent']['sha256'])
                assert len(parent) == trial['parent']['rank']
                assert sum(v.bit_count() for t in parent for v in t) == trial['parent']['density']
                end = load(directory/f'end-{index}.txt', shape, trial['end_parent']['sha256'])
                assert len(end) == trial['end_parent']['rank']
                ends += 1
                # Reports retain the generating absolute path as provenance;
                # resolve its relative suffix inside this copied study only.
                old_root = Path(options['output'])
                recipe_path = contained(path.parent, str(Path(trial['recipe']).relative_to(old_root)))
                recipe = read(recipe_path)
                assert recipe['field'] == 'GF(2)' and not recipe['record_claim']
                assert snapshot(recipe_path.parent, recipe['parent']) == parent
                assert sorted(i for g in recipe['groups'] for i in g['indices']) == list(range(len(parent)))
                total, formula = Counter(), 0
                for group in recipe['groups']:
                    leaf = snapshot(recipe_path.parent, group['leaf'])
                    formula += len(leaf)
                    total.update(expand_group(shape, parent, recipe['scale'], group, group['leaf']['shape'], leaf))
                final = snapshot(recipe_path.parent, recipe['result'])
                assert sorted(t for t, n in total.items() if n % 2) == sorted(final)
                assert recipe['result']['shape'] == [d*s for d, s in zip(shape, recipe['scale'])]
                assert formula == recipe['formula_rank'] == trial['score']
                assert len(final) == recipe['exact_rank'] == trial['exact_product_rank'] <= formula
                products += 1
    assert attempts == summary['total_attempts']
    with tempfile.TemporaryDirectory(prefix='metaflip-holdout-tensors-') as directory:
        tmp, tasks = Path(directory), []
        for i, ((shape, digest), body) in enumerate(tensors.items()):
            name = f'{i}.txt'
            (tmp/name).write_bytes(body)
            tasks.append((tmp, tensor.Record('x'.join(map(str, shape)), shape, len(body.splitlines()), name, digest)))
        with ProcessPoolExecutor(max_workers=workers, mp_context=multiprocessing.get_context('fork')) as pool:
            checked = list(pool.map(tensor._verify_one, tasks))
    return dict(complete=True, field='GF(2)', record_claim=False, throughput_claim=False,
        attempts=attempts, product_maps=products, end_states=ends, unique_tensors=len(checked),
        terms=sum(c.terms for c in checked), pair_xors=sum(c.pair_xors for c in checked),
        source_sha256=pins, results=[asdict(c) for c in checked])


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', required=True, type=Path)
    p.add_argument('--workers', type=int, choices=range(1, 5), default=2)
    p.add_argument('--report', type=Path)
    a = p.parse_args()
    result = verify(a.root, a.workers)
    if a.report:
        a.report.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('source_sha256', 'results')}))
