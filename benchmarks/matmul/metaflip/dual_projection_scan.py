#!/usr/bin/env python3
"""Bounded canonical dual-kernel restrictions of exact GF(2) MM tensors.

For nonzero u,v with u.v=1, construct M,N with kernels u,v and MN^T=I.
The finite family is a search strategy, not a claim about all future states.
"""
import argparse
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
import hashlib
from itertools import combinations, product
import json
import math
import multiprocessing
from pathlib import Path
import time

from extend_composition_parents import identity
from projection_composition_scan import EDGES, ProjectionCache, text, validate_keep
from verify_representation_portfolio import parse_terms


def dual_maps(n, u, v):
    if (type(n) is not int or n < 2 or type(u) is not int or type(v) is not int or
        not 0 < u < 1 << n or not 0 < v < 1 << n or (u & v).bit_count() % 2 != 1):
        raise ValueError('dual kernels must be nonzero n-bit vectors with odd inner product')
    pivot = (u & -u).bit_length()-1
    keep = tuple(i for i in range(n) if i != pivot)
    left = tuple((1 << i) ^ (((u >> i) & 1) << pivot) for i in keep)
    right = tuple((1 << i) ^ (u if (v >> i) & 1 else 0) for i in keep)
    return keep, left, right


def anchored_dual_family(shape, keep, all_anchors=False):
    """Balanced shell: each kernel is the deleted unit plus <=1 other unit.

    The canonical output basis can change with u; only the other dimensions'
    coordinate keeps are fixed. Include the ordinary coordinate control once.
    """
    validate_keep(shape, keep)
    dimensions = [i for i, n in enumerate(shape) if n-len(keep[i]) == 1]
    if type(all_anchors) is not bool: raise ValueError('all_anchors must be boolean')
    count = 1+sum((shape[i]*(shape[i]*(shape[i]-1)+1)-1 if all_anchors else
                   shape[i]*(shape[i]-1)) for i in dimensions)

    def generate():
        yield None
        for dimension in dimensions:
            n = shape[dimension]
            original, = set(range(n))-set(keep[dimension])
            for pivot in (range(n) if all_anchors else (original,)):
                anchor = 1 << pivot
                options = [anchor]+[anchor | (1 << i) for i in range(n) if i != pivot]
                for u, v in product(options, repeat=2):
                    if u == v == anchor and pivot == original: continue
                    if (u & v).bit_count() % 2:
                        yield dict(dimension=dimension, u=u, v=v)
    return count, generate()


class WordMap:
    """Map one shared coordinate after restricting the other coordinate."""
    def __init__(self, ids, words, n, other_extent, row_coordinate):
        self.ids, self.words = ids, words
        self.n, self.other, self.row_coordinate = n, other_extent, row_coordinate
        self.ordinary_cache, self.delta_cache = {}, {}
        if row_coordinate:
            mask = (1 << other_extent)-1
            self.row_chunks = []
            self.combinations = [] if n <= 8 else None
            for word in words:
                rows = tuple((word >> (i*other_extent)) & mask for i in range(n))
                self.row_chunks.append(rows)
                if self.combinations is not None:
                    sums = [0]
                    for bits in range(1, 1 << n):
                        low = bits & -bits
                        sums.append(sums[bits ^ low] ^ rows[low.bit_length()-1])
                    self.combinations.append(sums)
        else:
            mask = (1 << n)-1
            self.chunks = [tuple((word >> (i*n)) & mask for i in range(other_extent)) for word in words]
            self.needed_chunks = {chunk for chunks in self.chunks for chunk in chunks} if n > 8 else None

    @staticmethod
    def subset_xor(parts, bits):
        value = 0
        while bits:
            low = bits & -bits
            value ^= parts[low.bit_length()-1]
            bits ^= low
        return value

    def transform_delta(self, rows, coordinates):
        """Reuse coordinate images and requested XOR deltas, not full maps."""
        coordinates = tuple(coordinates)
        if (len(coordinates) != len(rows) or len(set(coordinates)) != len(coordinates) or
            any(type(i) is not int or not 0 <= i < self.n for i in coordinates) or
            any(type(row) is not int or not 0 <= row < 1 << self.n for row in rows)):
            raise ValueError('invalid coordinate baseline for word map')
        if coordinates not in self.ordinary_cache:
            if self.row_coordinate:
                base = tuple(sum(parts[j] << (i*self.other) for i, j in enumerate(coordinates))
                             for parts in self.row_chunks)
            else:
                base = tuple(sum(sum(((chunk >> j) & 1) << i for i, j in enumerate(coordinates)) << (r*len(rows))
                                 for r, chunk in enumerate(chunks)) for chunks in self.chunks)
            self.ordinary_cache[coordinates] = base
        words = list(self.ordinary_cache[coordinates])
        groups = {}
        for i, (row, coordinate) in enumerate(zip(rows, coordinates)):
            delta = row ^ (1 << coordinate)
            if delta: groups.setdefault(delta, []).append(i)
        for delta, positions in groups.items():
            key = delta, len(rows)
            if key not in self.delta_cache:
                if self.row_coordinate:
                    values = tuple(self.subset_xor(parts, delta) for parts in self.row_chunks)
                else:
                    values = tuple(sum(((chunk & delta).bit_count() % 2) << (r*len(rows))
                                       for r, chunk in enumerate(chunks)) for chunks in self.chunks)
                self.delta_cache[key] = values
            for j, value in enumerate(self.delta_cache[key]):
                for i in positions:
                    words[j] ^= value << (i*self.other if self.row_coordinate else i)
        return tuple(words[i] for i in self.ids)

    def transform(self, rows, coordinates=None):
        if self.n > 8 and coordinates is not None:
            return self.transform_delta(rows, coordinates)
        if self.row_coordinate:
            if self.combinations is not None:
                words = [sum(sums[row] << (i*self.other) for i, row in enumerate(rows))
                         for sums in self.combinations]
            else:
                # Evaluate requested row combinations only; n=32 must not
                # allocate 2**32 entries for every distinct factor word.
                words = [sum(self.subset_xor(chunks, row) << (i*self.other) for i, row in enumerate(rows))
                         for chunks in self.row_chunks]
        else:
            columns = [sum(((row >> j) & 1) << i for i, row in enumerate(rows)) for j in range(self.n)]
            if self.needed_chunks is None:
                lut = [0]
                for bits in range(1, 1 << self.n):
                    low = bits & -bits
                    lut.append(lut[bits ^ low] ^ columns[low.bit_length()-1])
            else:
                lut = {bits: self.subset_xor(columns, bits) for bits in self.needed_chunks}
            words = [sum(lut[chunk] << (i*len(rows)) for i, chunk in enumerate(chunks)) for chunks in self.chunks]
        return tuple(words[i] for i in self.ids)


class DualProjectionCache:
    def __init__(self, shape, terms):
        self.base = ProjectionCache(shape, terms)
        self.shape = self.base.shape
        self.prepared = {}

    def prepare(self, keep, dimension):
        validate_keep(self.shape, keep)
        if (type(dimension) is not int or dimension not in (0, 1, 2) or
            len(keep[dimension]) != self.shape[dimension]-1):
            raise ValueError('dual projection requires one fewer shared coordinate')
        full = list(map(tuple, keep))
        full[dimension] = tuple(range(self.shape[dimension]))
        key = tuple(full), dimension
        if key not in self.prepared:
            maps, unaffected = {}, None
            for axis, (a, b) in enumerate(EDGES):
                ids, words = self.base.column(axis, full[a], full[b])
                if dimension in (a, b):
                    maps[axis] = WordMap(ids, words, self.shape[dimension],
                                         len(full[b if a == dimension else a]), a == dimension)
                else:
                    unaffected = axis, tuple(words[i] for i in ids)
            self.prepared[key] = maps, unaffected, {}
        return self.prepared[key]

    def restrict(self, keep, dimension, u, v, materialize=True):
        actual_keep, left, right = dual_maps(self.shape[dimension], u, v)
        if tuple(keep[dimension]) != actual_keep:
            raise ValueError('keep must use the canonical least-pivot row order')
        maps, unaffected, left_cache = self.prepare(keep, dimension)
        first, second = sorted(maps)
        if u not in left_cache:
            left_cache[u] = maps[first].transform(left, actual_keep)
        columns = [None]*3
        columns[unaffected[0]] = unaffected[1]
        columns[first] = left_cache[u]
        columns[second] = maps[second].transform(right, actual_keep)
        parity = set()
        for term in zip(*columns):
            if all(term):
                if term in parity:
                    parity.remove(term)
                else:
                    parity.add(term)
        return sorted(parity) if materialize else parity


def scan_parent(job):
    entry, targets, prices, slack, allowance = job
    raw = Path(entry['path']).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == entry['sha256']
    terms = parse_terms(raw, entry['rank'])
    assert identity(entry['shape'], terms) == entry['identity']
    cache = DualProjectionCache(entry['shape'], terms)
    images, families, views = {}, [], 0
    start = time.process_time()
    for target in sorted(set(map(tuple, targets))):
        if any(k > n for k, n in zip(target, entry['shape'])):
            raise ValueError('target does not fit its oriented parent')
        baseline = prices[tuple(sorted(target))]
        for dimension, (n, k) in enumerate(zip(entry['shape'], target)):
            if n-k != 1:
                continue
            others = math.prod(math.comb(extent, count) for i, (extent, count) in
                               enumerate(zip(entry['shape'], target)) if i != dimension)
            count = others*((1 << n)-1)*(1 << (n-1))
            summary = dict(shape=target, dimension=dimension, views=count, baseline=baseline)
            if count > allowance:
                families.append(dict(summary, skipped=True, reason='per-family view allowance'))
                continue
            best, best_coordinate, checked = None, None, 0
            axes = [tuple(combinations(range(extent), size)) if i != dimension else (tuple(range(k)),)
                    for i, (extent, size) in enumerate(zip(entry['shape'], target))]
            for ordinary_keep in product(*axes):
                keep = list(ordinary_keep)
                for u in range(1, 1 << n):
                    pivot = (u & -u).bit_length()-1
                    keep[dimension] = tuple(i for i in range(n) if i != pivot)
                    for v in range(1, 1 << n):
                        if not (u & v).bit_count() % 2:
                            continue
                        child = cache.restrict(keep, dimension, u, v, False)
                        rank = len(child)
                        checked += 1
                        best = min(best if best is not None else rank, rank)
                        if u == v and u.bit_count() == 1:
                            best_coordinate = min(best_coordinate if best_coordinate is not None else rank, rank)
                        if rank <= baseline+slack:
                            child = sorted(child)
                            key = identity(target, child)
                            if key not in images:
                                images[key] = dict(shape=target, rank=rank, baseline=baseline,
                                    keep=tuple(keep), dual=dict(dimension=dimension, u=u, v=v),
                                    identity=key, terms=child)
            assert checked == count
            views += checked
            families.append(dict(summary, skipped=False, best=best, best_coordinate=best_coordinate))
    return dict(source=entry, parent=entry['id'], views=views, families=families,
                rows=list(images.values()), cpu_seconds=time.process_time()-start)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inputs', type=Path, required=True)
    p.add_argument('--prices', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--job', action='append', required=True, help='parent:oriented-shape, e.g. 21:2x2x7')
    p.add_argument('--slack', type=int, default=2)
    p.add_argument('--max-family-views', type=int, default=100000)
    p.add_argument('--workers', type=int, choices=range(1, 5), default=2)
    args = p.parse_args()
    assert not args.output.exists() and args.slack >= 0 and args.max_family_views > 0
    pins = {}
    def blob(path):
        path = Path(path).resolve()
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        assert pins.get(str(path), digest) == digest
        pins[str(path)] = digest
        return raw
    inputs, plan = json.loads(blob(args.inputs)), json.loads(blob(args.prices))
    assert all(r['complete'] and r['field'] == 'GF(2)' and not r['record_claim'] for r in (inputs, plan))
    targets = {}
    for job in args.job:
        source, shape = job.split(':')
        source, shape = int(source), tuple(map(int, shape.split('x')))
        assert 0 <= source < len(inputs['parents']) and len(shape) == 3 and min(shape) >= 2
        assert shape not in targets.setdefault(source, [])
        targets[source].append(shape)
    selected = [dict(inputs['parents'][i], id=i) for i in sorted(targets)]
    prices = {tuple(s): r['rank'] for s, r in zip(plan['model_shapes'], plan['baseline_recipes'])}
    old = {row['identity'] for row in inputs['parents']}
    for name in ('dual_projection_scan.py', 'projection_composition_scan.py', 'extend_composition_parents.py'):
        blob(Path(__file__).with_name(name))
    args.output.mkdir()
    (args.output / 'parents').mkdir()
    (args.output / 'tensors').mkdir()
    report = dict(complete=False, field='GF(2)', record_claim=False, canonical_archive_changed=False,
        redistribution_cleared=False, projection_kind='canonical_dual_kernel', selected_parents=len(selected),
        parents_done=0, views=0, rows=[], outputs=[], source_sha256=pins,
        limits=dict(slack=args.slack, max_family_views=args.max_family_views, jobs=args.job))
    start, seen, counts = time.monotonic(), set(), Counter()
    def save():
        report['elapsed_seconds'] = time.monotonic()-start
        report['counts'] = dict(counts)
        pending = args.output / 'report.pending.json'
        pending.write_text(json.dumps(report, indent=2)+'\n')
        pending.replace(args.output / 'report.json')
    save()
    with ProcessPoolExecutor(max_workers=args.workers, mp_context=multiprocessing.get_context('fork')) as pool:
        jobs = [(entry, targets[entry['id']], prices, args.slack, args.max_family_views) for entry in selected]
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
                data = text(child)
                digest = hashlib.sha256(data).hexdigest()
                name = 'tensors/'+'x'.join(map(str, row['shape']))+'-'+digest+'.txt'
                (args.output / name).write_bytes(data)
                row.update(path=name, sha256=digest, parent=entry['id'], parent_path=parent_name,
                    parent_shape=entry['shape'], parent_sha256=entry['sha256'],
                    improves_local=row['rank'] < row['baseline'])
                report['outputs'].append(row)
                counts['retained'] += 1
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
