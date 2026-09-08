#!/usr/bin/env python3
"""Refine audited coordinate winners with bounded folds, then exact pair cleanup.

Only the supplied keep sets and one-sided masks up to the requested Hamming
weight are searched. This is not an exhaustive linear-map or rank search.
"""
import argparse
import hashlib
from itertools import combinations
import json
from math import comb
from pathlib import Path
import time

from extend_composition_parents import identity
from fold_projection_scan import EDGES, FoldCache, JointFoldCache
from pair_reduction_scan import has_merge, reduce_pairs
from projection_composition_scan import text, validate_keep
from verify_representation_portfolio import contained, parse_terms


def fold_family(shape, keep, max_weight, max_axes=1):
    validate_keep(shape, keep)
    if type(max_weight) is not int or not 0 <= max_weight <= 3:
        raise ValueError('mask weight must be in 0..3')
    if type(max_axes) is not int or max_axes not in (1, 2, 3):
        raise ValueError('folded axes must be in 1..3')
    dimensions = [i for i, n in enumerate(shape) if n-len(keep[i]) == 1]
    if max_axes > 1:
        if any(n-len(k) not in (0, 1) for n, k in zip(shape, keep)):
            raise ValueError('joint folds require at most one deletion per axis')
        sizes = [2*sum(comb(len(keep[i]), k) for k in range(1, min(max_weight, len(keep[i]))+1))
                 for i in dimensions]
        count = 1
        for size in range(1, min(max_axes, len(sizes))+1):
            for subset in combinations(sizes, size):
                value = 1
                for n in subset: value *= n
                count += value

        def joint_generate():
            options = []
            for dimension in dimensions:
                axis = [None]
                for factor in range(3):
                    if dimension in EDGES[factor]:
                        for weight in range(1, min(max_weight, len(keep[dimension]))+1):
                            for bits in combinations(range(len(keep[dimension])), weight):
                                axis.append(dict(dimension=dimension, factor=factor, mask=sum(1 << i for i in bits)))
                options.append(axis)
            def extend(i, folds):
                if i == len(options):
                    yield folds
                    return
                for fold in options[i]:
                    if fold is None:
                        yield from extend(i+1, folds)
                    elif len(folds) < max_axes:
                        yield from extend(i+1, folds+[fold])
            yield from extend(0, [])
        return count, joint_generate()
    count = 1+sum(2*sum(comb(len(keep[i]), k) for k in range(1, min(max_weight, len(keep[i]))+1))
                  for i in dimensions)

    def generate():
        yield None
        for dimension in dimensions:
            for factor in range(3):
                if dimension in EDGES[factor]:
                    for weight in range(1, min(max_weight, len(keep[dimension]))+1):
                        for bits in combinations(range(len(keep[dimension])), weight):
                            yield dict(dimension=dimension, factor=factor, mask=sum(1 << i for i in bits))
    return count, generate()


def scan_map(entry, keep, baseline, max_weight=1, order=(0, 1, 2), max_views=2000, max_axes=1):
    if len(order) != 3 or any(type(i) is not int for i in order) or sorted(order) != [0, 1, 2]:
        raise ValueError('invalid pair order')
    count, family = fold_family(entry['shape'], keep, max_weight, max_axes)
    if type(max_views) is not int or max_views < count:
        raise ValueError(f'fold family needs {count} views, exceeding the allowance')
    start = time.process_time()
    raw = Path(entry['path']).read_bytes()
    if hashlib.sha256(raw).hexdigest() != entry['sha256']:
        raise ValueError('source changed')
    terms = parse_terms(raw, entry['rank'])
    cache = (FoldCache(entry['shape'], terms) if max_axes == 1 else JointFoldCache(entry['shape'], terms, keep))
    shape, fold_key = tuple(map(len, keep)), 'fold' if max_axes == 1 else 'folds'
    best, control, trials, changed = None, None, [], 0
    for fold in family:
        if max_axes > 1:
            child = cache.restrict(fold)
        else:
            child = (cache.base.restrict(keep, True) if fold is None else
                     cache.restrict(keep, fold['dimension'], fold['factor'], fold['mask']))
        raw_rank = len(child)
        child, trace = reduce_pairs(child, order) if has_merge(child) else (child, [])
        changed += bool(trace)
        row = dict(shape=shape, keep=keep, **{fold_key: fold}, rank=len(child), raw_rank=raw_rank,
                   baseline=baseline, reduction_order=order, reduction_trace=trace)
        if not fold:
            control = dict(raw_rank=raw_rank, rank=len(child))
        trials.append(dict(**{fold_key: fold}, raw_rank=raw_rank, rank=len(child)))
        if best is None or len(child) < best['rank']:
            best = dict(row, identity=identity(shape, child), terms=child)
    assert len(trials) == count
    return dict(views=count, control=control, pair_reduced_views=changed,
                raw_rank_pruning=False, trials=trials, winner=best,
                cpu_seconds=time.process_time()-start)


def run(seeds, prices_path, output, max_weight=1, order=(0, 1, 2), max_views=2000, max_axes=1):
    output = Path(output).resolve()
    if output.exists():
        raise ValueError('output must not exist')
    pins = {}

    def blob(path):
        path = Path(path).resolve()
        raw = path.read_bytes(); digest = hashlib.sha256(raw).hexdigest()
        if pins.get(str(path), digest) != digest:
            raise ValueError('input drift')
        pins[str(path)] = digest
        return raw

    def checked(value):
        if not value['complete'] or value['field'] != 'GF(2)' or value['record_claim']:
            raise ValueError('expected completed GF(2) evidence')

    plan = json.loads(blob(prices_path)); checked(plan)
    if len(plan['model_shapes']) != len(plan['baseline_recipes']):
        raise ValueError('price table mismatch')
    prices = {tuple(s): r['rank'] for s, r in zip(plan['model_shapes'], plan['baseline_recipes'])}
    selected = []
    for root, index in seeds:
        root = Path(root).resolve()
        raw = blob(root/'report.json'); source = json.loads(raw)
        audit = json.loads(blob(root/'independent-audit.json'))
        checked(source); checked(audit)
        if audit['report_sha256'] != hashlib.sha256(raw).hexdigest():
            raise ValueError('stale seed audit')
        if type(index) is not int or not 0 <= index < len(source['outputs']):
            raise ValueError('invalid seed output index')
        row = source['outputs'][index]
        if row.get('fold') is not None or row.get('folds'):
            raise ValueError('seed must be a coordinate map, not an existing fold')
        if audit['source_sha256'][row['path']] != row['sha256'] or hashlib.sha256(
                blob(contained(root, row['path']))).hexdigest() != row['sha256']:
            raise ValueError('seed tensor changed')
        path = contained(root, row['parent_path'])
        data = blob(path)
        if (audit['source_sha256'][row['parent_path']] != row['parent_sha256'] or
                hashlib.sha256(data).hexdigest() != row['parent_sha256']):
            raise ValueError('seed parent changed')
        entry = dict(shape=row['parent_shape'], path=str(path), sha256=row['parent_sha256'],
                     rank=int(data.splitlines()[0]))
        count, _ = fold_family(entry['shape'], row['keep'], max_weight, max_axes)
        if count > max_views:
            raise ValueError(f'fold family needs {count} views, exceeding the allowance')
        selected.append((entry, row['keep'], dict(root=str(root), index=index)))
    for name in ('refine_fold_projections.py', 'fold_projection_scan.py', 'projection_composition_scan.py',
                 'pair_reduction_scan.py', 'extend_composition_parents.py', 'verify_representation_portfolio.py'):
        blob(Path(__file__).with_name(name))
    output.mkdir(); (output/'parents').mkdir(); (output/'tensors').mkdir()
    report = dict(complete=False, field='GF(2)', record_claim=False, redistribution_cleared=False,
        canonical_archive_changed=False, projection_kind='bounded_fold_then_shared_pair_reduction',
        selected_parents=len(selected), parents_done=0, views=0, rows=[], outputs=[],
        source_sha256=pins, workers=1, gpu_used=False,
        limits=dict(max_mask_weight=max_weight, max_views_per_seed=max_views, pair_order=list(order),
                    fixed_keep_sets=True, raw_rank_pruning=False))
    if max_axes > 1:
        report['projection_kind'] = 'bounded_joint_fold_then_shared_pair_reduction'
        report['limits']['max_folded_axes'] = max_axes
    start, seen = time.monotonic(), set()

    def save():
        report['elapsed_seconds'] = time.monotonic()-start
        pending = output/'report.pending.json'
        pending.write_text(json.dumps(report, indent=2)+'\n')
        pending.replace(output/'report.json')

    save()
    for index, (entry, keep, seed) in enumerate(selected):
        result = scan_map(entry, keep, prices[tuple(sorted(map(len, keep)))], max_weight, order, max_views, max_axes)
        row = result.pop('winner'); child = row.pop('terms')
        if row['identity'] not in seen:
            seen.add(row['identity'])
            parent_name = f'parents/{index}.txt'; (output/parent_name).write_bytes(blob(entry['path']))
            data = text(child); digest = hashlib.sha256(data).hexdigest()
            name = 'tensors/'+'x'.join(map(str, row['shape']))+'-'+digest+'.txt'
            (output/name).write_bytes(data)
            row.update(path=name, sha256=digest, parent=index, parent_path=parent_name,
                       parent_shape=entry['shape'], parent_sha256=entry['sha256'],
                       improves_local=row['rank'] < row['baseline'])
            report['outputs'].append(row)
        result.update(seed=seed, best_rank=row['rank'], shape=row['shape'])
        report['rows'].append(result); report['parents_done'] += 1; report['views'] += result['views']
        save()
        print(json.dumps({k: v for k, v in result.items() if k != 'trials'}), flush=True)
    if any(hashlib.sha256(Path(path).read_bytes()).hexdigest() != digest for path, digest in pins.items()):
        raise ValueError('source changed during scan')
    report['complete'] = True; save()
    return report


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--seed', action='append', required=True, help='audited report directory:output index')
    p.add_argument('--prices', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--max-mask-weight', type=int, choices=range(4), default=1)
    p.add_argument('--max-folded-axes', type=int, choices=(1, 2, 3), default=1)
    p.add_argument('--max-views-per-seed', type=int, default=2000)
    p.add_argument('--pair-order', default='0,1,2')
    a = p.parse_args()
    seeds = [(root, int(index)) for root, index in (s.rsplit(':', 1) for s in a.seed)]
    run(seeds, a.prices, a.output, a.max_mask_weight, tuple(map(int, a.pair_order.split(','))), a.max_views_per_seed, a.max_folded_axes)
