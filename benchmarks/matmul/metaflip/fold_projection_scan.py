#!/usr/bin/env python3
"""Bounded one-sided XOR folding of a deleted matrix-multiplication coordinate.

One factor uses the ordinary coordinate map N. The other uses M=(I|v),
with M*N^T=I. Complete tensor verification remains the admission gate.
"""
import argparse
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
import hashlib
from itertools import combinations, permutations, product
import json
import math
import multiprocessing
from pathlib import Path
import time

from extend_composition_parents import identity
from projection_composition_scan import EDGES, ProjectionCache, restrict_word, text, validate_keep
from verify_representation_portfolio import parse_terms


class FoldValues:
    """Dense for tiny coordinates; otherwise O(width), not O(2**width), storage."""
    def __init__(self, value, additions):
        self.value, self.additions = value, tuple(additions)
        self.dense = None
        if len(additions) <= 8:
            self.dense = [value]
            for mask in range(1, 1 << len(additions)):
                bit = mask & -mask
                self.dense.append(self.dense[mask ^ bit] ^ additions[bit.bit_length()-1])

    def __getitem__(self, mask):
        if self.dense is not None:
            return self.dense[mask]
        value = self.value
        while mask:
            bit = mask & -mask
            value ^= self.additions[bit.bit_length()-1]
            mask ^= bit
        return value


class FoldCache:
    def __init__(self, shape, terms):
        self.base = ProjectionCache(shape, terms)
        self.shape = self.base.shape
        self.terms = self.base.terms
        self.tables = {}

    def prepare(self, keep, dimension, factor):
        validate_keep(self.shape, keep)
        if (type(dimension) is not int or dimension not in (0, 1, 2) or
            type(factor) is not int or factor not in (0, 1, 2) or dimension not in EDGES[factor] or
            len(keep[dimension]) != self.shape[dimension]-1):
            raise ValueError('fold requires one deleted shared coordinate')
        key = tuple(map(tuple, keep)), dimension, factor
        if key in self.tables:
            return self.tables[key]
        drop, = set(range(self.shape[dimension]))-set(keep[dimension])
        columns = [self.base.column(axis, keep[a], keep[b]) for axis, (a, b) in enumerate(EDGES)]
        streams = [tuple(words[i] for i in ids) for ids, words in columns]
        a, b = EDGES[factor]
        rows, cols = keep[a], keep[b]
        folded = {}
        for word in {term[factor] for term in self.terms}:
            value = restrict_word(word, self.shape[b], rows, cols)
            dropped = restrict_word(word, self.shape[b], (drop,) if a == dimension else rows,
                                    (drop,) if b == dimension else cols)
            if a == dimension:
                additions = [dropped << (i*len(cols)) for i in range(len(rows))]
            else:
                spread = sum(((dropped >> i) & 1) << (i*len(cols)) for i in range(len(rows)))
                additions = [spread << j for j in range(len(cols))]
            folded[word] = FoldValues(value, additions)
        self.tables[key] = streams, folded
        return streams, folded

    def restrict(self, keep, dimension, factor, mask, materialize=True):
        streams, folded = self.prepare(keep, dimension, factor)
        if type(mask) is not int or not 0 <= mask < 1 << len(keep[dimension]):
            raise ValueError('invalid fold mask')
        columns = list(streams)
        # Evaluate only requested masks, once per distinct word, including on
        # the lazy path. Repeated factor words do not repeat the XOR work.
        values = {word: table[mask] for word, table in folded.items()}
        columns[factor] = (values[term[factor]] for term in self.terms)
        parity = set()
        for term in zip(*columns):
            if all(term):
                if term in parity:
                    parity.remove(term)
                else:
                    parity.add(term)
        return sorted(parity) if materialize else len(parity)


class JointFoldCache:
    """Compose distinct-axis folds with only one cached prefix path.

    Intermediate images are not pair-reduced. Each axis map is linear, and
    distinct shared dimensions commute, even when they affect the same factor.
    Never retain the whole Cartesian tree of large intermediate tensors.
    """
    def __init__(self, shape, terms, keep):
        validate_keep(shape, keep)
        if any(n-len(k) not in (0, 1) for n, k in zip(shape, keep)):
            raise ValueError('joint folds require at most one deletion per axis')
        self.keep = tuple(map(tuple, keep))
        self.dimensions = tuple(i for i, n in enumerate(shape) if len(keep[i]) != n)
        self.caches, self.tokens = [FoldCache(shape, terms)], []

    def restrict(self, folds):
        chosen = {}
        for fold in folds:
            if set(fold) != {'dimension', 'factor', 'mask'}:
                raise ValueError('invalid joint fold fields')
            d, f, m = (fold[k] for k in ('dimension', 'factor', 'mask'))
            if (type(d) is not int or d not in self.dimensions or d in chosen or
                type(f) is not int or f not in range(3) or d not in EDGES[f] or
                type(m) is not int or not 0 < m < 1 << len(self.keep[d])):
                raise ValueError('invalid or repeated joint fold axis')
            chosen[d] = f, m
        if not self.dimensions:
            return self.caches[0].base.restrict(self.keep, True)
        for i, dimension in enumerate(self.dimensions):
            cache = self.caches[i]
            keep = [tuple(range(n)) for n in cache.shape]
            keep[dimension] = self.keep[dimension]
            token = chosen.get(dimension)
            if i < len(self.dimensions)-1 and i < len(self.tokens) and token == self.tokens[i]:
                continue
            child = (cache.base.restrict(keep, True) if token is None else
                     cache.restrict(keep, dimension, token[0], token[1]))
            if i == len(self.dimensions)-1:
                return child
            self.tokens = self.tokens[:i]+[token]
            self.caches = self.caches[:i+1]+[FoldCache(tuple(map(len, keep)), child)]


def scan_parent(job):
    entry, targets, prices, slack, allowance = job
    raw = Path(entry['path']).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == entry['sha256']
    terms = parse_terms(raw, entry['rank'])
    assert identity(entry['shape'], terms) == entry['identity']
    cache = FoldCache(entry['shape'], terms)
    images, rows, views = {}, [], 0
    start = time.process_time()
    for target in sorted({p for shape in targets for p in permutations(shape)}):
        if any(k > n for k, n in zip(target, entry['shape'])) or tuple(entry['shape']) == target:
            continue
        dimensions = [i for i, (n, k) in enumerate(zip(entry['shape'], target)) if n-k == 1]
        coordinate_count = math.prod(math.comb(n, k) for n, k in zip(entry['shape'], target))
        fold_count = coordinate_count * sum(2*((1 << target[i])-1) for i in dimensions)
        summary = dict(shape=target, coordinate_views=coordinate_count, fold_views=fold_count)
        if coordinate_count+fold_count > allowance:
            rows.append(dict(summary, skipped=True, reason='per-family view allowance'))
            continue
        baseline = prices[tuple(sorted(target))]
        best_coordinate, best_fold = None, None

        def retain(child, keep, fold):
            rank = len(child)
            if rank > baseline+slack:
                return
            key = identity(target, child)
            if key not in images:
                images[key] = dict(shape=target, rank=rank, baseline=baseline, keep=keep,
                    fold=fold, identity=key, terms=child)

        axes = [tuple(combinations(range(n), k)) for n, k in zip(entry['shape'], target)]
        for keep in product(*axes):
            child = cache.base.restrict(keep, True)
            best_coordinate = min(best_coordinate if best_coordinate is not None else len(child), len(child))
            retain(child, keep, None)
            views += 1
            for dimension in dimensions:
                for factor in range(3):
                    if dimension not in EDGES[factor]:
                        continue
                    for mask in range(1, 1 << target[dimension]):
                        child = cache.restrict(keep, dimension, factor, mask)
                        best_fold = min(best_fold if best_fold is not None else len(child), len(child))
                        retain(child, keep, dict(dimension=dimension, factor=factor, mask=mask))
                        views += 1
        rows.append(dict(summary, skipped=False, baseline=baseline,
                         best_coordinate=best_coordinate, best_fold=best_fold))
    return dict(source=entry, parent=entry['id'], views=views, families=rows,
                rows=list(images.values()), cpu_seconds=time.process_time()-start)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inputs', type=Path, required=True)
    p.add_argument('--prices', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--source-parent', type=int, action='append', required=True)
    p.add_argument('--target', action='append', required=True)
    p.add_argument('--slack', type=int, default=2)
    p.add_argument('--max-family-views', type=int, default=100000)
    p.add_argument('--workers', type=int, choices=range(1, 5), default=2)
    args = p.parse_args()
    assert not args.output.exists() and args.slack >= 0 and args.max_family_views > 0
    targets = [tuple(map(int, value.split('x'))) for value in args.target]
    assert all(len(s) == 3 and min(s) >= 2 for s in targets)
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
    ids = args.source_parent
    assert len(ids) == len(set(ids)) and all(0 <= i < len(inputs['parents']) for i in ids)
    selected = [dict(inputs['parents'][i], id=i) for i in ids]
    prices = {tuple(s): r['rank'] for s, r in zip(plan['model_shapes'], plan['baseline_recipes'])}
    old = {p['identity'] for p in inputs['parents']}
    for name in ('fold_projection_scan.py', 'projection_composition_scan.py', 'extend_composition_parents.py'):
        blob(Path(__file__).with_name(name))
    args.output.mkdir()
    (args.output / 'parents').mkdir()
    (args.output / 'tensors').mkdir()
    report = dict(complete=False, field='GF(2)', record_claim=False, canonical_archive_changed=False,
        redistribution_cleared=False, projection_kind='coordinate_or_one_sided_fold',
        selected_parents=len(selected), parents_done=0, views=0, rows=[], outputs=[], source_sha256=pins,
        limits=dict(slack=args.slack, max_family_views=args.max_family_views, targets=targets, source_parents=ids))
    start, seen, counts = time.monotonic(), set(), Counter()
    def save():
        report['elapsed_seconds'] = time.monotonic()-start
        report['counts'] = dict(counts)
        pending = args.output / 'report.pending.json'
        pending.write_text(json.dumps(report, indent=2) + '\n')
        pending.replace(args.output / 'report.json')
    save()
    with ProcessPoolExecutor(max_workers=args.workers, mp_context=multiprocessing.get_context('fork')) as pool:
        jobs = [(entry, targets, prices, args.slack, args.max_family_views) for entry in selected]
        for result in pool.map(scan_parent, jobs):
            entry = result.pop('source')
            raw = blob(entry['path'])
            assert hashlib.sha256(raw).hexdigest() == entry['sha256']
            parent_name = f"parents/{entry['id']}.txt"
            (args.output / parent_name).write_bytes(raw)
            for row in result.pop('rows'):
                key = row['identity']
                if key in old or key in seen:
                    counts['prior_identity' if key in old else 'repeated_identity'] += 1
                    continue
                seen.add(key)
                child = row.pop('terms')
                data, tag = text(child), 'x'.join(map(str, row['shape']))
                digest = hashlib.sha256(data).hexdigest()
                name = 'tensors/' + tag + '-' + digest + '.txt'
                (args.output / name).write_bytes(data)
                row.update(path=name, sha256=digest, parent=entry['id'], parent_path=parent_name,
                    parent_shape=entry['shape'], parent_sha256=entry['sha256'],
                    improves_local=row['rank'] < row['baseline'])
                report['outputs'].append(row)
                counts['retained_fold' if row['fold'] else 'retained_coordinate'] += 1
            report['rows'].append(result)
            report['parents_done'] += 1
            report['views'] += result['views']
            save()
            print(json.dumps(dict(parent=entry['id'], views=result['views'], families=result['families'],
                retained=len(report['outputs']), elapsed=report['elapsed_seconds'])), flush=True)
    assert all(hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest for path, digest in pins.items())
    report['complete'] = True
    save()
    print(json.dumps({k: v for k, v in report.items() if k not in ('rows', 'outputs', 'source_sha256')}), flush=True)


if __name__ == '__main__':
    main()
