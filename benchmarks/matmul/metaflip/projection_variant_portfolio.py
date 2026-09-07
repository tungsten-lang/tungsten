#!/usr/bin/env python3
"""Keep distinct near-best coordinate images, including nonminimum images.

This offline bounded search preserves full oriented literal identity. Its
outputs require verify_coordinate_projections.py before composition admission.
No shape/rank/histogram equivalence is used to collapse parent representations.
"""
import argparse
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
import hashlib
from itertools import product
import json
import multiprocessing
from pathlib import Path
import time

from extend_composition_parents import identity
from projection_composition_scan import ProjectionCache, families, text
from verify_representation_portfolio import parse_terms


def scan_parent(job):
    entry, prices, slack, minimum_dimension, targets, max_views = job
    if type(slack) is not int or slack < 0 or minimum_dimension < 1:
        raise ValueError('invalid retention allowance')
    start = time.process_time()
    raw = Path(entry['path']).read_bytes()
    if hashlib.sha256(raw).hexdigest() != entry['sha256']:
        raise ValueError('source hash changed')
    terms = parse_terms(raw, entry['rank'])
    shape = tuple(entry['shape'])
    if identity(shape, terms) != entry['identity']:
        raise ValueError('source identity changed')
    cache = ProjectionCache(shape, terms)
    full = tuple(tuple(range(n)) for n in shape)
    seen, images, minima = set(), {}, {}
    skipped, counts, accepted = [], {}, 0
    for name, axes, count in families(shape, targets, max_views):
        if axes is None:
            skipped.append(dict(family=name, views=count, reason='per-family allowance'))
            continue
        checked = 0
        for keep in product(*axes):
            if keep == full or keep in seen:
                continue
            seen.add(keep)
            checked += 1
            target = tuple(map(len, keep))
            if min(target) < minimum_dimension:
                continue
            rank = cache.restrict(keep)
            minima[target] = min(minima.get(target, rank), rank)
            baseline = prices[tuple(sorted(target))]
            if rank > baseline + slack:
                continue
            accepted += 1
            child = cache.restrict(keep, True)
            assert len(child) == rank
            key = identity(target, child)
            if key not in images:
                images[key] = dict(shape=target, rank=rank, baseline=baseline,
                    keep=keep, identity=key, terms=child)
        counts[name] = checked
    for row in images.values():
        row['parent_minimum_rank'] = minima[row['shape']]
        row['above_parent_minimum'] = row['rank'] > row['parent_minimum_rank']
    return dict(parent=entry['id'], source=entry, views=len(seen), families=counts,
        skipped=skipped, eligible_views=accepted, distinct_images=len(images),
        within_parent_duplicates=accepted-len(images), rows=list(images.values()),
        cpu_seconds=time.process_time()-start)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--prices', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--source-parent', type=int, action='append')
    parser.add_argument('--slack', type=int, default=2)
    parser.add_argument('--minimum-dimension', type=int, default=2)
    parser.add_argument('--max-source-rank', type=int, default=512)
    parser.add_argument('--max-source-dimension', type=int, default=12)
    parser.add_argument('--max-family-views', type=int, default=20000)
    parser.add_argument('--target', action='append', default=[])
    parser.add_argument('--workers', type=int, choices=range(1, 5), default=2)
    args = parser.parse_args()
    if args.slack < 0 or min(args.minimum_dimension, args.max_source_rank,
                            args.max_source_dimension, args.max_family_views) < 1:
        parser.error('invalid retention or search allowance')
    if args.output.exists():
        parser.error('output must not exist')
    targets = [tuple(map(int, s.split('x'))) for s in args.target]
    if any(len(s) != 3 or min(s) < 1 for s in targets):
        parser.error('invalid target shape')
    pins = {}

    def blob(path):
        path = Path(path).resolve()
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        assert pins.get(str(path), digest) == digest
        pins[str(path)] = digest
        return data

    inputs = json.loads(blob(args.inputs))
    plan = json.loads(blob(args.prices))
    for report in (inputs, plan):
        assert report['complete'] and report['field'] == 'GF(2)' and not report['record_claim']
    assert len(plan['model_shapes']) == len(plan['baseline_recipes'])
    prices = {tuple(s): r['rank'] for s, r in zip(plan['model_shapes'], plan['baseline_recipes'])}
    prior = {p['identity'] for p in inputs['parents']}
    assert len(prior) == len(inputs['parents'])
    wanted = None if args.source_parent is None else set(args.source_parent)
    if wanted is not None and (len(wanted) != len(args.source_parent) or
        any(i < 0 or i >= len(inputs['parents']) for i in wanted)):
        parser.error('invalid or repeated source parent')
    selected = [dict(p, id=i) for i, p in enumerate(inputs['parents'])
        if (wanted is None or i in wanted) and p['rank'] <= args.max_source_rank
        and max(p['shape']) <= args.max_source_dimension and min(p['shape']) >= 2]
    if wanted is not None and wanted != {e['id'] for e in selected}:
        parser.error('an explicitly selected parent is excluded by source limits')
    args.output.mkdir()
    (args.output / 'parents').mkdir()
    (args.output / 'tensors').mkdir()
    for name in ('projection_variant_portfolio.py', 'projection_composition_scan.py',
                 'extend_composition_parents.py', 'verify_representation_portfolio.py'):
        blob(Path(__file__).with_name(name))
    report = dict(complete=False, field='GF(2)', record_claim=False,
        canonical_archive_changed=False, redistribution_cleared=False,
        source_sha256=pins, selection='All full-identity-distinct eligible images; not only parent minima.',
        limits=dict(slack=args.slack, minimum_dimension=args.minimum_dimension,
            max_source_rank=args.max_source_rank, max_source_dimension=args.max_source_dimension,
            max_family_views=args.max_family_views, targets=targets, source_parents=args.source_parent),
        selected_parents=len(selected), parents_done=0, views=0, rows=[], outputs=[],
        counts={}, source_cpu_seconds=0)
    start = time.monotonic()
    counts, seen = Counter(), set()

    def save():
        report['counts'] = dict(counts)
        report['elapsed_seconds'] = time.monotonic()-start
        pending = args.output / 'report.pending.json'
        pending.write_text(json.dumps(report, indent=2) + '\n')
        pending.replace(args.output / 'report.json')

    def job(entry):
        possible = {tuple(sorted(s)) for s in product(*[(n, max(1, n-1)) for n in entry['shape']])}
        possible.update(tuple(sorted(s)) for s in targets)
        small_prices = {s: prices[s] for s in possible if min(s) >= args.minimum_dimension and s in prices}
        return entry, small_prices, args.slack, args.minimum_dimension, targets, args.max_family_views

    save()
    with ProcessPoolExecutor(max_workers=args.workers, mp_context=multiprocessing.get_context('fork')) as pool:
        for result in pool.map(scan_parent, map(job, selected)):
            entry = result.pop('source')
            parent_name = f"parents/{entry['id']}.txt"
            retained = []
            for row in result.pop('rows'):
                key = row['identity']
                reason = 'prior_exact_identity' if key in prior else 'repeat_exact_identity' if key in seen else None
                if reason:
                    counts[reason] += 1
                    continue
                seen.add(key)
                terms = row.pop('terms')
                data = text(terms)
                digest = hashlib.sha256(data).hexdigest()
                name = 'tensors/' + 'x'.join(map(str, row['shape'])) + '-' + digest + '.txt'
                (args.output / name).write_bytes(data)
                counts['retained'] += 1
                counts['above_parent_minimum' if row['above_parent_minimum'] else 'at_parent_minimum'] += 1
                row.update(parent=entry['id'], parent_shape=entry['shape'], parent_path=parent_name,
                    parent_sha256=entry['sha256'], path=name, sha256=digest,
                    improves_local=row['rank'] < row['baseline'])
                retained.append(row)
                report['outputs'].append(row)
            if retained:
                raw = blob(entry['path'])
                assert hashlib.sha256(raw).hexdigest() == entry['sha256']
                (args.output / parent_name).write_bytes(raw)
            result['retained'] = len(retained)
            report['rows'].append(result)
            report['views'] += result['views']
            report['source_cpu_seconds'] += result['cpu_seconds']
            report['parents_done'] += 1
            if report['parents_done'] % 25 == 0:
                save()
                print(json.dumps(dict(done=report['parents_done'], total=len(selected),
                    views=report['views'], retained=counts['retained'], elapsed=report['elapsed_seconds'])), flush=True)
    assert all(hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest for path, digest in pins.items())
    report['complete'] = True
    save()
    print(json.dumps({k: v for k, v in report.items() if k not in ('rows', 'outputs', 'source_sha256')}), flush=True)


if __name__ == '__main__':
    main()
