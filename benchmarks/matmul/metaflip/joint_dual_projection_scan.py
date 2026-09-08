#!/usr/bin/env python3
"""Bounded simultaneous dual-kernel restrictions in two shared coordinates.

No rank filter is applied between the two restrictions. Coordinate and
single-coordinate controls are included in the same exact enumeration.
Retained full identities require independent replay before composition use.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import time

from dual_projection_scan import DualProjectionCache, dual_maps
from extend_composition_parents import identity
from pair_reduction_scan import reduce_pairs
from projection_composition_scan import text
from verify_representation_portfolio import parse_terms


def kernel_pairs(n):
    if type(n) is not int or not 2 <= n <= 8:
        raise ValueError('shared dimensions must be integers in 2..8')
    return tuple((u, v) for u in range(1, 1 << n) for v in range(1, 1 << n)
                 if (u & v).bit_count() % 2)


def coordinate_pair(pair):
    u, v = pair
    return u == v and u.bit_count() == 1


def changed_dimensions(shape, target):
    if (len(shape) != 3 or len(target) != 3 or
        any(type(n) is not int or not 2 <= n <= 32 for n in (*shape, *target))):
        raise ValueError('invalid parent/target shape')
    dims = tuple(i for i in range(3) if shape[i] != target[i])
    if len(dims) != 2 or any(shape[i]-target[i] != 1 for i in dims):
        raise ValueError('exactly two coordinates must shrink by one')
    for i in dims:
        kernel_pairs(shape[i])
    return dims


def scan(shape, terms, target, baseline, slack=0, prior=(), cpu_limit=120.0, pair_order=None):
    dims = changed_dimensions(shape, target)
    if (type(baseline) is not int or baseline < 1 or type(slack) is not int or
        slack < 0 or not 0 < cpu_limit < float('inf')):
        raise ValueError('invalid rank or CPU allowance')
    if pair_order is not None:
        reduce_pairs([], pair_order)  # Strictly validate the requested deterministic rewrite order.
    pairs = [kernel_pairs(shape[d]) for d in dims]
    prior = set(prior)
    original = DualProjectionCache(shape, terms)
    full = tuple(tuple(range(n)) for n in shape)
    start = time.process_time()
    images, minima, raw_minima, counts, histograms = {}, {}, {}, Counter(), {}
    intermediate_best = None
    planned = len(pairs[0])*len(pairs[1])
    views = 0
    for first in pairs[0]:
        if time.process_time()-start >= cpu_limit:
            break
        keep = list(full)
        keep[dims[0]] = dual_maps(shape[dims[0]], *first)[0]
        intermediate = original.restrict(keep, dims[0], *first)
        intermediate_best = min(intermediate_best or len(intermediate), len(intermediate))
        middle_shape = tuple(map(len, keep))
        second_cache = DualProjectionCache(middle_shape, intermediate)
        # This deliberately does not consult an intermediate price/rank gate.
        middle_keep = [tuple(range(n)) for n in middle_shape]
        for second in pairs[1]:
            middle_keep[dims[1]] = dual_maps(shape[dims[1]], *second)[0]
            child = second_cache.restrict(middle_keep, dims[1], *second, False)
            keep[dims[1]] = middle_keep[dims[1]]
            changed = sum(not coordinate_pair(p) for p in (first, second))
            kind = ('coordinate', 'single_dual', 'joint_dual')[changed]
            raw_rank = len(child)
            raw_minima[kind] = min(raw_minima.get(kind, raw_rank), raw_rank)
            trace = []
            if pair_order is not None:
                # No raw-rank gate: high raw rank can hide large exact pair cancellations.
                child, trace = reduce_pairs(child, pair_order)
                counts['pair_reduced_views'] += bool(trace)
            rank = len(child)
            counts[kind] += 1
            histograms.setdefault(kind, Counter())[rank] += 1
            minima[kind] = min(minima.get(kind, rank), rank)
            views += 1
            if rank <= baseline+slack:
                child = sorted(child)
                key = identity(target, child)
                if key in prior:
                    counts['prior_identity_views'] += 1
                elif key in images:
                    counts['repeated_retained_views'] += 1
                else:
                    images[key] = dict(shape=list(target), rank=rank, raw_rank=raw_rank, baseline=baseline,
                        keep=[list(k) for k in keep], identity=key, terms=child,
                        control_kind=kind, intermediate_rank=len(intermediate),
                        reduction_order=list(pair_order) if pair_order is not None else None,
                        reduction_trace=trace,
                        duals=[dict(dimension=d, u=p[0], v=p[1]) for d, p in zip(dims, (first, second))])
    return dict(complete=views == planned, views=views, planned_views=planned,
        dimensions=list(dims), minima=minima, raw_minima=raw_minima, counts=dict(counts),
        rank_histograms={k: dict(sorted(v.items())) for k, v in histograms.items()},
        best_intermediate_rank=intermediate_best, intermediate_rank_pruning=False,
        rows=list(images.values()), cpu_seconds=time.process_time()-start)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inputs', type=Path, required=True)
    p.add_argument('--prices', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--job', action='append', required=True, help='parent:oriented-target, e.g. 88:4x4x5')
    p.add_argument('--slack', type=int, default=0)
    p.add_argument('--max-job-views', type=int, default=300000)
    p.add_argument('--cpu-seconds-per-job', type=float, default=120.0)
    p.add_argument('--pair-order', help='Exact shared-pair cleanup before rank retention, e.g. 0,1,2')
    a = p.parse_args()
    if a.output.exists() or a.slack < 0 or a.max_job_views < 1 or not 0 < a.cpu_seconds_per_job < float('inf'):
        p.error('output must be new and allowances must be positive (slack may be zero)')
    pair_order = tuple(map(int, a.pair_order.split(','))) if a.pair_order is not None else None
    if pair_order is not None:
        reduce_pairs([], pair_order)
    pins = {}

    def blob(path):
        path = Path(path).resolve()
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        if pins.get(str(path), digest) != digest:
            raise ValueError('input changed')
        pins[str(path)] = digest
        return raw

    inputs, prices = (json.loads(blob(path)) for path in (a.inputs, a.prices))
    for r in (inputs, prices):
        if not r['complete'] or r['field'] != 'GF(2)' or r['record_claim']:
            p.error('expected completed GF(2) input screens')
    if len(prices['model_shapes']) != len(prices['baseline_recipes']):
        p.error('price table length mismatch')
    price = {tuple(s): r['rank'] for s, r in zip(prices['model_shapes'], prices['baseline_recipes'])}
    jobs = []
    for description in a.job:
        source, target = description.split(':')
        source, target = int(source), tuple(map(int, target.split('x')))
        if not 0 <= source < len(inputs['parents']) or (source, target) in jobs:
            p.error('invalid or repeated parent/target')
        shape = inputs['parents'][source]['shape']
        dims = changed_dimensions(shape, target)
        if len(kernel_pairs(shape[dims[0]]))*len(kernel_pairs(shape[dims[1]])) > a.max_job_views:
            p.error('job exceeds view allowance')
        if tuple(sorted(target)) not in price:
            p.error('target has no prior price')
        jobs.append((source, target))
    for name in ('joint_dual_projection_scan.py', 'dual_projection_scan.py',
                 'projection_composition_scan.py', 'extend_composition_parents.py', 'pair_reduction_scan.py'):
        blob(Path(__file__).with_name(name))
    a.output.mkdir()
    (a.output/'parents').mkdir()
    (a.output/'tensors').mkdir()
    prior = {row['identity'] for row in inputs['parents']}
    report = dict(complete=False, field='GF(2)', record_claim=False, canonical_archive_changed=False,
        redistribution_cleared=False, projection_kind='joint_canonical_dual_kernel', workers=1,
        selected_parents=len(jobs), parents_done=0, views=0, rows=[], outputs=[], source_sha256=pins,
        limits=dict(slack=a.slack, max_job_views=a.max_job_views,
                    cpu_seconds_per_job=a.cpu_seconds_per_job, pair_order=pair_order, jobs=a.job))
    start = time.monotonic()

    def save():
        report['elapsed_seconds'] = time.monotonic()-start
        pending = a.output/'report.pending.json'
        pending.write_text(json.dumps(report, indent=2)+'\n')
        pending.replace(a.output/'report.json')

    save()
    for source, target in jobs:
        entry = inputs['parents'][source]
        raw = blob(entry['path'])
        if hashlib.sha256(raw).hexdigest() != entry['sha256']:
            raise ValueError('source hash mismatch')
        terms = parse_terms(raw, entry['rank'])
        if identity(entry['shape'], terms) != entry['identity']:
            raise ValueError('source identity mismatch')
        parent_name = f'parents/{source}.txt'
        (a.output/parent_name).write_bytes(raw)
        result = scan(entry['shape'], terms, target, price[tuple(sorted(target))],
                      a.slack, prior, a.cpu_seconds_per_job, pair_order)
        for row in result.pop('rows'):
            data = text(row.pop('terms'))
            digest = hashlib.sha256(data).hexdigest()
            name = 'tensors/'+'x'.join(map(str, target))+'-'+digest+'.txt'
            (a.output/name).write_bytes(data)
            row.update(path=name, sha256=digest, parent=source, parent_path=parent_name,
                       parent_shape=entry['shape'], parent_sha256=entry['sha256'],
                       improves_local=row['rank'] < row['baseline'])
            report['outputs'].append(row)
            prior.add(row['identity'])
        result.update(parent=source, parent_path=parent_name, parent_shape=entry['shape'],
                      parent_sha256=entry['sha256'], target=list(target), baseline=price[tuple(sorted(target))])
        report['rows'].append(result)
        report['views'] += result['views']
        report['parents_done'] += 1
        save()
        print(json.dumps(dict(parent=source, **{k: result[k] for k in
            ('complete', 'views', 'minima', 'cpu_seconds')}, retained=len(report['outputs']))), flush=True)
        if not result['complete']:
            break
    if any(hashlib.sha256(Path(path).read_bytes()).hexdigest() != digest for path, digest in pins.items()):
        raise ValueError('pinned input changed during scan')
    report['complete'] = report['parents_done'] == len(jobs) and all(r['complete'] for r in report['rows'])
    save()


if __name__ == '__main__':
    main()
