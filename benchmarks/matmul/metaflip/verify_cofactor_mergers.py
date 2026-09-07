#!/usr/bin/env python3
"""Independent replay of finite cofactor joins and complete GF(2) witnesses.

Every pair in the retained proposal pools is scored, without the Ruby sparse
join's pruning. This does not certify an unrestricted orbit or a world record.
"""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor
from dataclasses import asdict
import hashlib
import importlib.util
from itertools import permutations, product
import json
import multiprocessing
from pathlib import Path
import sys
import tempfile

from verify_representation_portfolio import apply_word, contained, identity, parse_terms
from verify_matrix_pockets import EDGES, image_report, positions, rank


def parity(terms):
    return [t for t, count in Counter(map(tuple, terms)).items() if count % 2]


def cofactor(terms, axis):
    assert axis in range(3)
    other = [a for a in range(3) if a != axis]
    result = defaultdict(int)
    for term in terms:
        assert len(term) == 3 and all(isinstance(v, int) and 0 < v < 1 << 256 for v in term)
        result[tuple(term[a] for a in other)] ^= term[axis]
    return {key: value for key, value in result.items() if value}


def materialize(table, axis):
    other = [a for a in range(3) if a != axis]
    result = []
    for key, value in table.items():
        term = [0, 0, 0]
        term[axis] = value
        for a, v in zip(other, key):
            term[a] = v
        result.append(tuple(term))
    return result


def matrix_factors(pairs, *, max_bits=256, reverse_columns=False):
    """Canonical column basis, independently solved by row equations.

    Ruby incrementally encodes each column during elimination. Here basis
    selection uses rank tests, then a separate low-pivot row system solves
    all right factors simultaneously. Every output matrix is reconstructed.
    """
    assert type(max_bits) is int and 1 <= max_bits <= 4096
    assert type(reverse_columns) is bool
    columns = defaultdict(int)
    for left, right in pairs:
        assert all(type(v) is int and 0 <= v < 1 << max_bits for v in (left, right))
        for j in positions(right):
            columns[j] ^= left
    basis = []
    for j in sorted(columns, reverse=reverse_columns):
        if rank(basis + [columns[j]]) > len(basis):
            basis.append(columns[j])
    equations = {}
    for coordinate in range(max((v.bit_length() for v in basis), default=0)):
        mask = sum(((v >> coordinate) & 1) << i for i, v in enumerate(basis))
        rhs = sum(((v >> coordinate) & 1) << j for j, v in columns.items())
        while mask:
            pivot = (mask & -mask).bit_length() - 1
            if pivot not in equations:
                equations[pivot] = mask, rhs
                break
            row, value = equations[pivot]
            mask ^= row
            rhs ^= value
        if not mask:
            assert rhs == 0, 'inconsistent matrix coordinate system'
    assert len(equations) == len(basis)
    solved = {}
    for pivot in sorted(equations, reverse=True):
        mask, rhs = equations[pivot]
        for i in positions(mask ^ (1 << pivot)):
            rhs ^= solved[i]
        solved[pivot] = rhs
    factors = [(v, solved[i]) for i, v in enumerate(basis)]
    actual = defaultdict(int)
    for left, right in factors:
        assert left and right
        for j in positions(right):
            actual[j] ^= left
    assert {j: v for j, v in actual.items() if v} == {j: v for j, v in columns.items() if v}
    return factors


def refactor_shared(terms, axis, *, max_bits=256, reverse_columns=False):
    assert type(axis) is int and axis in range(3)
    assert type(max_bits) is int and 1 <= max_bits <= 4096
    assert type(reverse_columns) is bool
    assert all(len(t)==3 and all(type(v) is int and 0<v<1<<max_bits for v in t) for t in terms)
    groups=defaultdict(list)
    for t in terms:groups[t[axis]].append(tuple(t))
    other=[a for a in range(3) if a!=axis];out=[];changed=[]
    for fixed,group in groups.items():
        if len(group)<2:
            out.extend(group)
            continue
        factors=matrix_factors([(t[other[0]],t[other[1]]) for t in group],
                               max_bits=max_bits,reverse_columns=reverse_columns)
        replacement=[]
        for left,right in factors:
            t=[0,0,0];t[axis]=fixed;t[other[0]]=left;t[other[1]]=right
            replacement.append(tuple(t))
        if sorted(replacement)!=sorted(group):
            changed.append(dict(fixed=fixed,before=len(group),after=len(replacement)))
        out.extend(replacement)
    out=parity(out)
    assert len(out)<=len(terms)
    return out,changed


def compress_shared(terms, *, max_bits=256):
    """Reconstruct stable grouping, exact rank drops, and every pass."""
    assert type(max_bits) is int and 1 <= max_bits <= 4096
    assert all(len(t) == 3 and all(type(v) is int and 0 < v < 1 << max_bits for v in t) for t in terms)
    terms = list(map(tuple, terms))
    history = []
    while True:
        before = len(terms)
        for axis in range(3):
            other = [a for a in range(3) if a != axis]
            groups = defaultdict(list)
            for term in terms:
                groups[term[axis]].append(term)
            ordered = []
            for fixed, group in groups.items():
                if len(group) < 2 or (len(group) == 2 and all(group[0][a] != group[1][a] for a in other)):
                    ordered.extend(group)
                    continue
                factors = matrix_factors([(t[other[0]], t[other[1]]) for t in group], max_bits=max_bits)
                assert len(factors) <= len(group)
                if len(factors) == len(group):
                    ordered.extend(group)
                    continue
                history.append(dict(axis=axis, fixed=fixed, before=len(group), after=len(factors)))
                for left, right in factors:
                    term = [0, 0, 0]
                    term[axis], term[other[0]], term[other[1]] = fixed, left, right
                    ordered.append(tuple(term))
            terms = parity(ordered)
        assert len(terms) <= before
        if len(terms) == before:
            return terms, history


def replay_compression(terms, expected_history):
    compressed, history = compress_shared(terms)
    assert history == expected_history, 'matrix compression history mismatch'
    return compressed


def cartesian_minimum(left, right, details=None, width=None, slack=0):
    """Encode collisions as bitsets, then visit the *entire* Cartesian grid."""
    assert left and right
    if width is not None:
        assert type(width) is int and 1 <= width <= 128
        assert type(slack) is int and 0 <= slack <= 16 and details is not None
    strata, eligible = defaultdict(list), Counter()
    keys = [set().union(*(set(m) for m in pool)) for pool in (left, right)]
    common = keys[0] & keys[1]
    key_index = {key: i for i, key in enumerate(sorted(common))}
    full = [set().union(*(set(m.items()) for m in pool)) for pool in (left, right)]
    full_index = {key: i for i, key in enumerate(sorted(full[0] & full[1]))}
    encoded = [[(len(m), sum(1 << key_index[k] for k in m if k in key_index),
                 sum(1 << full_index[kv] for kv in m.items() if kv in full_index))
                for m in pool] for pool in (left, right)]
    best = None
    best_colliding = None
    collisions = 0
    for i, (n, keys_a, full_a) in enumerate(encoded[0]):
        for j, (m, keys_b, full_b) in enumerate(encoded[1]):
            overlap = (keys_a & keys_b).bit_count()
            collisions += overlap > 0
            row = n + m - overlap - (full_a & full_b).bit_count(), i, j
            if width is not None:
                eligible[row[0]] += 1
                if len(strata[row[0]]) < width:
                    strata[row[0]].append(row)
            if best is None or row < best:
                best = row
            if overlap and (best_colliding is None or row < best_colliding):
                best_colliding = row
    if details is not None:
        details['best_colliding_pair'] = best_colliding
        if width is not None:
            details['ranked_candidates'] = [row for s in range(slack+1) for row in strata[best[0]+s]]
            details['eligible_by_rank'] = [eligible[best[0]+s] for s in range(slack+1)]
    return best, dict(possible_pairs=len(left)*len(right), collision_pairs=collisions,
                      common_keys=len(common), left_states=len(left), right_states=len(right))


def compression_assessment(pools, others, axis, candidate):
    score, i, j = candidate
    fused = materialize(cofactor(materialize(pools[0][i], axis) + materialize(pools[1][j], axis), axis), axis)
    assert len(fused) == score
    native = parity(others + fused)
    compressed, history = compress_shared(native)
    body = str(len(compressed))+'\n'+''.join(' '.join(map(str, t))+'\n' for t in sorted(compressed))
    return dict(indices=[i,j], cofactor_rank=score, bound=len(others)+score,
                rank=len(compressed), density=sum(v.bit_count() for t in compressed for v in t),
                compressed_sha256=hashlib.sha256(body.encode()).hexdigest(), compression=history)


def mapped(parent_shape, parent_term, allocation, shape, terms):
    # Build the images of individual coordinate bits independently of Ruby's
    # cached word/block implementation; then extend each map by XOR.
    images = []
    for a, (r, c) in enumerate(EDGES):
        ro = [sum(allocation[r][:i]) for i in range(parent_shape[r])]
        co = [sum(allocation[c][:i]) for i in range(parent_shape[c])]
        columns = sum(allocation[c])
        units = []
        for i, j in product(range(shape[r]), range(shape[c])):
            value = 0
            for bit in positions(parent_term[a]):
                row, col = divmod(bit, parent_shape[c])
                if i < allocation[r][row] and j < allocation[c][col]:
                    value ^= 1 << ((ro[row]+i)*columns + co[col]+j)
            units.append(value)
        images.append(units)
    result = []
    for term in terms:
        out = []
        for a, word in enumerate(term):
            value = 0
            for bit in positions(word):
                value ^= images[a][bit]
            out.append(value)
        if all(out):
            result.append(tuple(out))
    return parity(result)


def orient(shape, terms, target):
    if list(shape) == list(target):
        return terms
    permutation = next(p for p in permutations(range(3)) if [shape[i] for i in p] == list(target))
    result = []
    for term in terms:
        out = []
        for r, c in EDGES:
            r, c = permutation[r], permutation[c]
            edge = EDGES.index(tuple(sorted((r, c))))
            value = term[edge]
            if r > c:
                rows, columns = shape[c], shape[r]
                value = sum(1 << ((bit % columns)*rows + bit//columns) for bit in positions(value))
            out.append(value)
        result.append(tuple(out))
    return result


def verify(root, workers=2):
    root = root.resolve()
    read = lambda p: json.loads(p.read_text())
    report = read(root/'report.json')
    assert report['complete'] and report['field'] == 'GF(2)' and not report['record_claim']
    assert not report['redistribution_cleared']
    width, slack = report.get('compression_width', 1), report.get('compression_slack', 0)
    assert type(width) is int and 1 <= width <= 128
    assert type(slack) is int and 0 <= slack <= 16
    for name, digest in report.get('retained_files', {}).items():
        assert hashlib.sha256(contained(root, name).read_bytes()).hexdigest() == digest, name
    cases = {}
    def add(shape, terms):
        body = ''.join('R '+' '.join(map(str, t))+'\n' for t in terms).encode()
        cases[(tuple(shape), hashlib.sha256(body).hexdigest())] = body
    def load(base, entry):
        raw = contained(base, entry['path']).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == entry['sha256']
        lines = [s for s in raw.decode().splitlines() if s.strip() and not s.lstrip().startswith('#')]
        n = int(lines[0]) if lines[0].strip().isdigit() else len(lines)
        terms = parse_terms(raw, n)
        add(entry['shape'], terms)
        return terms
    def recipe(name):
        path = contained(root, name)
        data = read(path)
        assert (data['kind'], data['field']) == ('outer-basis-block', 'GF(2)')
        assert not data['record_claim']
        parent = load(path.parent, data['parent'])
        leaves = [load(path.parent, e) if e else None for e in data['leaves']]
        parts = [mapped(data['parent']['shape'], parent[i], data['allocation'], e['shape'], leaves[i])
                 if e else [] for i, e in enumerate(data['leaves'])]
        result = load(path.parent, data['result'])
        composed = orient(list(map(sum, data['allocation'])), parity(t for p in parts for t in p), data['result']['shape'])
        assert sorted(composed) == sorted(result) and len(result) == data['exact_rank']
        return data, parent, leaves, parts
    totals = Counter()
    gains = []
    joins = []
    for row in report['rows']:
        data, parent, leaves, parts = recipe(row['initial_recipe'])
        assert row['target'] == data['result']['shape']
        assert sum(map(len, parts)) == row['initial_rank'] == data['exact_rank']
        images = image_report(data['parent']['shape'], parent, data['allocation'],
                              [e['shape'] if e else None for e in data['leaves']])
        assert images == row['images'] and images['all_disjoint']
        eligible = {(tuple(p['slots']), p['intersection_dimensions'].index(0))
                    for p in images['pairs'] if p['intersection_dimensions'].count(0) == 1}
        assert eligible == {(tuple(c['slots']), c['axis']) for c in row['cases']}
        cache = {}
        for case in row['cases']:
            descriptions = read(contained(root, case['proposals']))
            assert len(descriptions) == 2
            pools = []
            selected_raw = []
            for side, (slot, states) in enumerate(zip(case['slots'], descriptions)):
                pool = []
                seen = set()
                shape = data['leaves'][slot]['shape']
                for i, entry in enumerate(states):
                    assert (entry['slot'], entry['index']) == (slot, i)
                    word = entry['action']['word']
                    if entry['action']['kind'] in ('kernel_pair', 'kernel_triple'):
                        components = entry['action']['components']
                        count = 2 if entry['action']['kind'] == 'kernel_pair' else 3
                        assert len(components) == count and len({p['axis'] for p in components}) == count
                        assert all(p['kind'] == 'kernel' for p in components)
                        assert word == [move for p in components for move in p['word']]
                    if i == 0:
                        assert entry['action'] == dict(kind='identity', word=[])
                    key = slot, tuple(map(tuple, word))
                    if key not in cache:
                        raw = apply_word(shape, leaves[slot], word)
                        terms = mapped(data['parent']['shape'], parent[slot], data['allocation'], shape, raw)
                        cache[key] = raw, terms
                        totals['unique_proposals_replayed'] += 1
                    raw, terms = cache[key]
                    assert identity(shape, raw) == entry['raw_id']
                    signature = tuple(sorted(terms))
                    assert signature not in seen
                    seen.add(signature)
                    table = cofactor(terms, case['axis'])
                    digest = hashlib.sha256(json.dumps(sorted(table.items()), separators=(',', ':')).encode()).hexdigest()
                    assert (len(terms), len(table), digest) == (entry['mapped_rank'], entry['cofactor_rank'], entry['cofactor_sha256'])
                    pool.append(table)
                    if i == case['indices'][side]:
                        assert case['selected'][side] == {k: entry[k] for k in ('action', 'raw_id')}
                        selected_raw.append(raw)
                        add(shape, raw)
                pools.append(pool)
            details = {}
            width, slack = report.get('compression_width', 1), report.get('compression_slack', 0)
            post = width > 1 or slack > 0
            assert post == ('postcompression' in case)
            best, counts = cartesian_minimum(*pools, details=details, width=width if post else None, slack=slack)
            a, b = case['slots']
            others = [t for slot, part in enumerate(parts) if slot not in (a, b) for t in part]
            selected_score = best[0]
            if post:
                claim = case['postcompression']
                assert claim['policy'] == 'first-index-pairs-per-cofactor-rank' and claim['exhaustive_final_rank'] is False
                assert claim['minimum'] == list(best)
                assert claim['eligible_by_rank'] == details.pop('eligible_by_rank')
                expected = [compression_assessment(pools, others, case['axis'], c) for c in details.pop('ranked_candidates')]
                assert claim['assessments'] == expected, 'postcompression assessment mismatch'
                selected = min(range(len(expected)), key=lambda k: (expected[k]['rank'], expected[k]['density'], *expected[k]['indices']))
                assert type(claim['selected']) is int and claim['selected'] == selected
                assert expected[selected]['indices'] == case['indices']
                assert (case['rank'], case['density']) == (expected[selected]['rank'], expected[selected]['density'])
                selected_score = expected[selected]['cofactor_rank']
                totals['compression_assessments_replayed'] += len(expected)
            else:
                assert list(best[1:]) == case['indices']
            assert all(case[k] == v for k, v in counts.items())
            totals.update(counts)
            i, j = case['indices']
            fused = materialize(pools[0][i], case['axis']) + materialize(pools[1][j], case['axis'])
            reduced = materialize(cofactor(fused, case['axis']), case['axis'])
            assert len(reduced) == selected_score
            assert len(others)+len(reduced) == case['bound']
            native = load(root, case['native_fused'])
            assert sorted(parity(others+reduced)) == sorted(native)
            assert case['native_fused']['shape'] == list(map(sum, data['allocation']))
            changed, new_parent, new_leaves, _ = recipe(case['product_recipe'])
            assert new_parent == parent and changed['allocation'] == data['allocation']
            expected = list(leaves)
            for slot, raw in zip(case['slots'], selected_raw):
                expected[slot] = raw
            assert all(sorted(x) == sorted(y) for x, y in zip(expected, new_leaves))
            compressed = replay_compression(native, case['compression'])
            final = load(root, case['result'])
            assert final == orient(case['native_fused']['shape'], compressed, row['target'])
            assert len(final) == case['rank']
            assert sum(v.bit_count() for t in final for v in t) == case['density']
            assert case['rank'] <= case['bound'] and case['rank'] <= row['initial_rank']
            if 'merge_recipe' in case:
                merge = read(contained(root, case['merge_recipe']))
                assert (merge['schema'], merge['kind'], merge['field'], merge['record_claim']) == (
                    1, 'outer-cofactor-merge', 'GF(2)', False)
                for k in ('product_recipe', 'slots', 'axis', 'bound', 'compression', 'native_fused', 'result', 'density'):
                    assert merge[k] == case[k]
                assert merge['exact_rank'] == case['rank']
                assert merge['product_sha256'] == hashlib.sha256(contained(root, case['product_recipe']).read_bytes()).hexdigest()
            joins.append(dict(target=row['target'], slots=case['slots'], axis=case['axis'],
                              minimum_pair_rank=best[0], final_rank=len(final), **counts, **details))
            if case['rank'] < row['initial_rank']:
                gains.append(dict(target=row['target'], before=row['initial_rank'], after=case['rank'],
                                  density=case['density'], result=case['result']))
        print(json.dumps(dict(replayed=row['target'], pools=len(cache))), flush=True)
    checker = root/'tools/verify_block_composition_records.py'
    if not checker.exists():
        checker = Path(__file__).with_name('verify_block_composition_records.py')
    spec = importlib.util.spec_from_file_location('cofactor_tensor_check', checker)
    tensor = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = tensor
    spec.loader.exec_module(tensor)
    with tempfile.TemporaryDirectory(prefix='metaflip-cofactor-check-') as directory:
        temporary = Path(directory)
        jobs = []
        for i, ((shape, digest), body) in enumerate(cases.items()):
            name = f'{i}.txt'
            (temporary/name).write_bytes(body)
            jobs.append((temporary, tensor.Record('x'.join(map(str, shape)), shape,
                                                 len(body.splitlines()), name, digest)))
        if workers == 1:
            results = list(map(tensor._verify_one, jobs))
        else:
            with ProcessPoolExecutor(max_workers=workers, mp_context=multiprocessing.get_context('fork')) as pool:
                results = list(pool.map(tensor._verify_one, jobs))
    return dict(schema=1, field='GF(2)', record_claim=False, complete=True,
                tensors=len(results), terms=sum(r.terms for r in results),
                pair_xors=sum(r.pair_xors for r in results), joins=joins, totals=dict(totals),
                local_rank_gains=gains, results=[asdict(r) for r in results])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', required=True, type=Path)
    parser.add_argument('--workers', type=int, choices=range(1, 5), default=2)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = verify(args.root, args.workers)
    if args.report:
        args.report.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'results'}))
