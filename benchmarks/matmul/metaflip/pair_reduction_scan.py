#!/usr/bin/env python3
"""Exact shared-pair cleanup of checked GF(2) tensor representations.

(a,b,c)+(a,b,d)=(a,b,c XOR d). Six cyclic axis orders are searched;
their normal forms are constructive candidates, not globally minimal ranks.
"""
import argparse
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
import hashlib
from itertools import permutations
import json
import multiprocessing
from pathlib import Path
import time

from extend_composition_parents import identity
from projection_composition_scan import text
from verify_representation_portfolio import parse_terms


def has_merge(terms):
    for axis in range(3):
        other = [j for j in range(3) if j != axis]
        seen = set()
        for term in terms:
            key = tuple(term[j] for j in other)
            if key in seen:
                return True
            seen.add(key)
    return False


def reduce_pairs(terms, order=(0, 1, 2)):
    if len(order) != 3 or any(type(i) is not int for i in order) or sorted(order) != [0, 1, 2]:
        raise ValueError('axis order must be a permutation of 0,1,2')
    terms = sorted(map(tuple, terms))
    if any(len(t) != 3 or any(type(v) is not int or v <= 0 for v in t) for t in terms):
        raise ValueError('input factors must be positive integer bit masks')
    trace = []
    while True:
        changed = False
        for axis in order:
            others = [j for j in range(3) if j != axis]
            groups = {}
            for term in terms:
                key = tuple(term[j] for j in others)
                groups[key] = groups.get(key, 0) ^ term[axis]
            child = []
            for key, value in groups.items():
                if value:
                    term = [0, 0, 0]
                    term[axis] = value
                    for j, v in zip(others, key):
                        term[j] = v
                    child.append(tuple(term))
            assert len(child) <= len(terms)
            if len(child) < len(terms):
                trace.append(dict(axis=axis, before=len(terms), after=len(child)))
                changed = True
            terms = sorted(child)
        if not changed:
            return terms, trace


def scan_parent(job):
    entry, price, slack = job
    raw = Path(entry['path']).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == entry['sha256']
    terms = parse_terms(raw, entry['rank'])
    assert identity(entry['shape'], terms) == entry['identity']
    start, candidates, views = time.process_time(), {}, 0
    best, mergeable = entry['rank'], has_merge(terms)
    if mergeable:
        for order in permutations(range(3)):
            child, trace = reduce_pairs(terms, order)
            views += 1
            best = min(best, len(child))
            if len(child) <= price+slack:
                key = identity(entry['shape'], child)
                candidates.setdefault(key, dict(shape=entry['shape'], rank=len(child), baseline=price,
                    keep=[list(range(n)) for n in entry['shape']], reduction_order=order,
                    reduction_trace=trace, identity=key, terms=child))
    return dict(source=entry, parent=entry['id'], source_rank=entry['rank'], shape=entry['shape'],
                mergeable=mergeable, best=best, baseline=price, views=views,
                rows=list(candidates.values()), cpu_seconds=time.process_time()-start)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inputs', type=Path, required=True)
    p.add_argument('--prices', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--max-source-rank', type=int, default=20000)
    p.add_argument('--slack', type=int, default=2)
    p.add_argument('--workers', type=int, choices=range(1, 5), default=2)
    args = p.parse_args()
    assert not args.output.exists() and args.max_source_rank > 0 and args.slack >= 0
    pins = {}
    def blob(path):
        path = Path(path).resolve()
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        assert pins.get(str(path), digest) == digest
        pins[str(path)] = digest
        return data
    inputs, plan = json.loads(blob(args.inputs)), json.loads(blob(args.prices))
    assert all(r['complete'] and r['field'] == 'GF(2)' and not r['record_claim'] for r in (inputs, plan))
    prices = {tuple(s): r['rank'] for s, r in zip(plan['model_shapes'], plan['baseline_recipes'])}
    selected = [dict({key: parent[key] for key in ('path', 'shape', 'rank', 'identity', 'sha256')}, id=i)
                for i, parent in enumerate(inputs['parents']) if parent['rank'] <= args.max_source_rank]
    prior = {parent['identity'] for parent in inputs['parents']}
    for name in ('pair_reduction_scan.py', 'projection_composition_scan.py', 'extend_composition_parents.py'):
        blob(Path(__file__).with_name(name))
    args.output.mkdir()
    (args.output/'parents').mkdir()
    (args.output/'tensors').mkdir()
    report = dict(complete=False, field='GF(2)', record_claim=False, canonical_archive_changed=False,
        redistribution_cleared=False, projection_kind='shared_pair_reduction',
        selected_parents=len(selected), skipped_parents=len(inputs['parents'])-len(selected),
        parents_done=0, views=0, rows=[], outputs=[], source_sha256=pins,
        limits=dict(slack=args.slack, max_source_rank=args.max_source_rank, axis_orders=6))
    start, counts, seen = time.monotonic(), Counter(), set()
    def save():
        report['elapsed_seconds'] = time.monotonic()-start
        report['counts'] = dict(counts)
        pending = args.output/'report.pending.json'
        pending.write_text(json.dumps(report, indent=2)+'\n')
        pending.replace(args.output/'report.json')
    save()
    with ProcessPoolExecutor(max_workers=args.workers, mp_context=multiprocessing.get_context('fork')) as pool:
        jobs = [(entry, prices[tuple(sorted(entry['shape']))], args.slack) for entry in selected]
        for result in pool.map(scan_parent, jobs, chunksize=4):
            entry = result.pop('source')
            rows = result.pop('rows')
            counts['mergeable'] += int(result['mergeable'])
            for row in rows:
                key = row['identity']
                if key in prior or key in seen:
                    counts['prior_identity' if key in prior else 'repeated_identity'] += 1
                    continue
                seen.add(key)
                parent_name = f"parents/{entry['id']}.txt"
                if not (args.output/parent_name).exists():
                    raw = blob(entry['path'])
                    assert hashlib.sha256(raw).hexdigest() == entry['sha256']
                    (args.output/parent_name).write_bytes(raw)
                child = row.pop('terms')
                data = text(child)
                digest = hashlib.sha256(data).hexdigest()
                name = 'tensors/'+'x'.join(map(str, row['shape']))+'-'+digest+'.txt'
                (args.output/name).write_bytes(data)
                row.update(path=name, sha256=digest, parent=entry['id'], parent_path=parent_name,
                    parent_shape=entry['shape'], parent_sha256=entry['sha256'],
                    improves_local=row['rank'] < row['baseline'])
                report['outputs'].append(row)
                counts['retained'] += 1
                if row['improves_local']:
                    print(json.dumps(dict(candidate=row['shape'], rank=row['rank'], baseline=row['baseline'],
                                          source=entry['id'])), flush=True)
            report['rows'].append(result)
            report['views'] += result['views']
            report['parents_done'] += 1
            if report['parents_done'] % 500 == 0:
                save()
                print(json.dumps(dict(done=report['parents_done'], total=len(selected),
                    mergeable=counts['mergeable'], retained=counts['retained'], elapsed=report['elapsed_seconds'])), flush=True)
    assert all(hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest for path, digest in pins.items())
    report['complete'] = True
    save()
    print(json.dumps({k: v for k, v in report.items() if k not in ('rows', 'outputs', 'source_sha256')}), flush=True)


if __name__ == '__main__':
    main()
