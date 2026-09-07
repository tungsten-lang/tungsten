#!/usr/bin/env python3
"""Independent pocket-census, macro-witness and image-intersection replay.

This checks exact GF(2) identities, not novelty or unrestricted rank optimality.
"""
from __future__ import annotations
import argparse
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor
from dataclasses import asdict
import hashlib
import importlib.util
from itertools import combinations, product
import json
import multiprocessing
from pathlib import Path
import sys
import tempfile

from verify_representation_portfolio import contained, parse_terms

EDGES = ((0, 1), (1, 2), (0, 2))


def rank(words):
    rows = {}
    for word in words:
        assert isinstance(word, int) and word >= 0
        while word:
            pivot = word.bit_length()
            if pivot in rows:
                word ^= rows[pivot]
            else:
                rows[pivot] = word
                break
    return len(rows)


def positions(word):
    assert isinstance(word, int) and word >= 0
    while word:
        low = word & -word
        yield low.bit_length() - 1
        word ^= low


def signature(terms):
    result = set()
    for a, b, c in terms:
        for point in product(positions(a), positions(b), positions(c)):
            if point in result:
                result.remove(point)
            else:
                result.add(point)
    return result


def unreduced_group_order(terms):
    """Replay the stable grouping in a compression pass with no reductions.

    An empty history does not mean unchanged *ordering*. Check that every
    encountered matrix really has full summand rank before preserving it.
    """
    count = len(terms)
    for axis in range(3):
        other = [a for a in range(3) if a != axis]
        groups = defaultdict(list)
        for term in terms:
            groups[term[axis]].append(term)
        ordered = []
        for group in groups.values():
            if len(group) >= 2:
                columns = defaultdict(int)
                for term in group:
                    for j in positions(term[other[1]]):
                        columns[j] ^= term[other[0]]
                assert rank(columns.values()) == len(group), 'unrecorded matrix reduction'
            ordered.extend(group)
        terms = [t for t, n in Counter(ordered).items() if n % 2]
    assert len(terms) == count
    return terms


def small_ranks():
    words = [sum(1 << (4*i + 2*j + k) for i, j, k in signature([t]))
             for t in product(range(1, 16), range(1, 4), range(1, 4))]
    distance = [4] * 65536
    distance[0] = 0
    for word in words:
        distance[word] = 1
    for a, b in combinations(words, 2):
        distance[a ^ b] = min(distance[a ^ b], 2)
    for a, b, c in combinations(words, 3):
        distance[a ^ b ^ c] = min(distance[a ^ b ^ c], 3)
    return distance


def pocket_code(terms, axis):
    other = [a for a in range(3) if a != axis]
    palettes = []
    for a in other:
        values = sorted({t[a] for t in terms})
        x, y = values[0], next((v for v in values if v != values[0]), 0)
        palette = [0, x, y, x ^ y]
        assert all(v in palette for v in values)
        palettes.append(palette)
    columns = [0] * 4
    for term in terms:
        b, c = [palettes[j].index(term[a]) for j, a in enumerate(other)]
        for j, k in product(range(2), repeat=2):
            if b >> j & c >> k & 1:
                columns[2*j+k] ^= term[axis]
    # Independent coordinate construction: explicitly expand the <=4-vector
    # column span, then label each column by its basis subset.
    span = {0: 0}
    dimension = 0
    for column in columns:
        if column not in span:
            span.update({v ^ column: code | (1 << dimension) for v, code in list(span.items())})
            dimension += 1
    bits = sum(((span[column] >> i) & 1) << (4*i+j)
               for j, column in enumerate(columns) for i in range(4))
    return bits, dimension


def pockets(terms):
    for axis in range(3):
        other = [a for a in range(3) if a != axis]
        cells = defaultdict(list)
        for i, term in enumerate(terms):
            cells[tuple(term[a] for a in other)].append(i)
        seen = set()
        for x, y in combinations(sorted(cells), 2):
            if x[0] == y[0] or x[1] == y[1]:
                continue
            palette = [tuple(sorted((x[a], y[a], x[a] ^ y[a]))) for a in range(2)]
            ids = tuple(sorted(i for pair in product(*palette) for i in cells.get(pair, ())))
            if len(ids) < 3 or ids in seen:
                continue
            seen.add(ids)
            yield axis, ids


def image_report(parent_shape, parent_terms, allocation, leaf_shapes):
    spaces = []
    for slot, leaf in enumerate(leaf_shapes):
        parts = []
        for axis, (r, c) in enumerate(EDGES):
            vectors = []
            if leaf is not None:
                row_offsets = [sum(allocation[r][:i]) for i in range(parent_shape[r])]
                col_offsets = [sum(allocation[c][:i]) for i in range(parent_shape[c])]
                total_columns = sum(allocation[c])
                for i, j in product(range(leaf[r]), range(leaf[c])):
                    v = 0
                    for bit in positions(parent_terms[slot][axis]):
                        row, col = divmod(bit, parent_shape[c])
                        if i < allocation[r][row] and j < allocation[c][col]:
                            v ^= 1 << ((row_offsets[row] + i)*total_columns + col_offsets[col] + j)
                    vectors.append(v)
            parts.append(vectors)
        spaces.append(parts)
    ranks = [[rank(part) for part in parts] for parts in spaces]
    pairs = []
    for i, j in combinations(range(len(spaces)), 2):
        dims = [ranks[i][a] + ranks[j][a] - rank(spaces[i][a] + spaces[j][a]) for a in range(3)]
        pairs.append(dict(slots=[i, j], intersection_dimensions=dims, disjoint=0 in dims))
    return dict(factor_ranks=ranks, pairs=pairs, all_disjoint=all(p['disjoint'] for p in pairs))


def verify(root, workers=2):
    root = root.resolve()
    read = lambda path: json.loads(path.read_text())
    manifest = read(root / 'report.json')
    assert manifest['complete'] and manifest['field'] == 'GF(2)' and not manifest['record_claim']
    for name, digest in manifest['retained_files'].items():
        assert hashlib.sha256(contained(root, name).read_bytes()).hexdigest() == digest, name
    cases = {}
    def add(terms, shape):
        terms = [tuple(t) for t in terms]
        body = ''.join('R ' + ' '.join(map(str, t)) + '\n' for t in terms).encode()
        key = tuple(shape), hashlib.sha256(body).hexdigest()
        cases[key] = body
        return terms
    def load(base, entry):
        raw = contained(base, entry['path']).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == entry['sha256']
        lines = [s for s in raw.decode().splitlines() if s.strip() and not s.lstrip().startswith('#')]
        n = int(lines[0]) if lines[0].strip().isdigit() else len(lines)
        return add(parse_terms(raw, n), entry['shape'])
    def recipe(base, name):
        path = contained(base, name)
        data = read(path)
        parent = load(path.parent, data['parent'])
        for leaf in data['leaves']:
            if leaf is not None:
                load(path.parent, leaf)
        load(path.parent, data['result'])
        return data, parent
    distances = small_ranks()
    census = transitions = 0
    pocket_summaries = {}
    for name in manifest['pocket_passes']:
        base = root / name
        report = read(base / 'report.json')
        gains = 0
        for row in report['rows']:
            current = load(base, row['source'])
            assert not row['matrix_history']
            assert (len(current), sum(v.bit_count() for t in current for v in t)) == (row['initial_rank'], row['initial_density'])
            current = unreduced_group_order(current)
            for step in row['passes']:
                if not report.get('variants', False):
                    sizes = Counter(); dims = Counter(); count = 0
                    for axis, ids in pockets(current):
                        bits, dim = pocket_code([current[i] for i in ids], axis)
                        assert distances[bits] == len(ids), 'missed reducing pocket'
                        count += 1; sizes[len(ids)] += 1; dims[dim] += 1
                    assert count == step['pockets']
                    assert {str(k): v for k, v in sizes.items()} == step['sizes']
                    assert {str(k): v for k, v in dims.items()} == step['dimensions']
                    census += count
                best = step['best']
                if best is None:
                    continue
                ids = best['indices']
                assert len(set(ids)) == len(ids) and all(0 <= i < len(current) for i in ids)
                old = [current[i] for i in ids]
                replacement = [tuple(t) for t in best['replacement']]
                assert signature(old) == signature(replacement)
                bits, _ = pocket_code(old, best['axis'])
                assert len(replacement) == distances[bits]
                assert not best.get('compression', [])
                candidate = [t for i, t in enumerate(current) if i not in ids] + replacement
                candidate = [t for t, n in Counter(candidate).items() if n % 2]
                if 'terms' in best:
                    candidate = unreduced_group_order(candidate)
                    assert candidate == list(map(tuple, best['terms']))
                before = len(current), sum(v.bit_count() for t in current for v in t)
                after = len(candidate), sum(v.bit_count() for t in candidate for v in t)
                assert after < before
                if 'terms' in best:
                    assert list(after) == best['key']
                add(candidate, row['target'])
                current = add(unreduced_group_order(candidate), row['target'])
                transitions += 1
            final = load(base, row['result'])
            assert Counter(final) == Counter(current)
            assert (len(final), sum(v.bit_count() for t in final for v in t)) == (row['rank'], row['density'])
            gains += row['rank'] < row['initial_rank']
        pocket_summaries[name] = dict(targets=len(report['rows']), rank_gains=gains,
            density_gains=sum(r['density'] < r['initial_density'] for r in report['rows']))
    image_base = root / 'image-spaces'
    images = read(image_base / 'report.json')
    checked_pairs = 0
    image_recipes = {}
    for row in images['rows']:
        data, parent = recipe(image_base, row['recipe'])
        actual = image_report(data['parent']['shape'], parent, data['allocation'],
            [e['shape'] if e else None for e in data['leaves']])
        assert actual == {k: row[k] for k in actual}
        assert actual['all_disjoint']
        image_recipes[tuple(row['target'])] = data
        checked_pairs += len(actual['pairs'])
    joins = read(root / 'delta-join/report.json')
    assert joins['complete']
    pair_total = 0
    for row in joins['rows']:
        initial, _ = recipe(root / 'delta-join', row['initial_recipe'])
        final, _ = recipe(root / 'delta-join', row['recipe'])
        geometry = image_recipes[tuple(row['target'])]
        assert initial['allocation'] == geometry['allocation']
        for key in ('parent', 'leaves'):
            if key == 'leaves':
                assert [e['sha256'] if e else None for e in initial[key]] == [e['sha256'] if e else None for e in geometry[key]]
            else:
                assert initial[key]['sha256'] == geometry[key]['sha256']
        assert initial['result']['sha256'] == final['result']['sha256']
        assert row['singles'] == 0 and not row['history']
        stats = row['join']; sizes = [p['proposals'] for p in row['per_slot']]
        assert sum(sizes) == row['unique_proposals'] == stats['proposals']
        assert stats['possible_pairs'] == (sum(sizes)**2 - sum(s*s for s in sizes)) // 2
        for key in ('collision_pairs', 'lower_bound_survivors', 'rank_gain_pairs', 'shared_new_terms'):
            assert stats[key] == 0
        assert stats['best'] is None
        pair_total += stats['possible_pairs']
    fleet = read(root / 'fleet/report.json')
    for entry in fleet['witnesses']:
        load(root / 'fleet', entry)
    walk = read(root / 'pocket-walk/report.json')
    assert walk['complete'] and [r['arm'] for r in walk['rows']] == ['control', 'pocket']
    walk_attempts = 0
    for arm in walk['rows']:
        source = load(root / 'pocket-walk', arm['source'])
        assert len(source) == arm['rank']
        assert sum(v.bit_count() for t in source for v in t) == arm['density']
        logs = [json.loads(line) for line in (root / 'pocket-walk' / (arm['arm'] + '.log')).read_text().splitlines()]
        assert len(logs) == len(arm['runs']) == walk['trials']
        for index, (log, run) in enumerate(zip(logs, arm['runs'])):
            assert {k: run[k] for k in log} == log
            assert run['trial'] == index and run['attempts'] == walk['attempts']
            assert run['initial_rank'] == arm['rank']
            assert run['plus_every'] == 65536 and run['restart_every'] == 250000 and run['compress_every'] == 8192
            assert 0 <= run['flips'] + run['pluses'] <= run['attempts']
            assert run['pluses'] <= run['attempts'] // run['plus_every']
            assert run['restarts'] == (run['attempts'] - 1) // run['restart_every']
            assert run['compression_calls'] == run['attempts'] // run['compress_every']
            assert run['checks'] >= 3 + run['attempts'] // 100000
            for key in ('result', 'final'):
                terms = load(root / 'pocket-walk', run[key + '_witness'])
                raw = contained(root / 'pocket-walk' / arm['arm'], run[key]).read_bytes()
                assert hashlib.sha256(raw).hexdigest() == run[key + '_witness']['sha256']
                if key == 'result':
                    assert len(terms) == run['rank'] <= arm['rank']
                    assert sum(v.bit_count() for t in terms for v in t) == run['density']
            walk_attempts += run['attempts']
    left, right = walk['rows']
    assert left['environment'] == right['environment']
    assert left['command'][2:9] == right['command'][2:9]
    seed_row = next(r for r in read(root / 'variants/report.json')['rows'] if r['target'] == walk['shape'])
    assert left['source']['sha256'] == seed_row['source']['sha256']
    assert right['source']['sha256'] == seed_row['result']['sha256']
    assert hashlib.sha256((root / 'pocket-walk/tools/wide-cancellation').read_bytes()).hexdigest() == walk['binary_sha256']
    checker = root / 'tools/verify_block_composition_records.py'
    spec = importlib.util.spec_from_file_location('pocket_tensor_checker', checker)
    tensor = importlib.util.module_from_spec(spec); sys.modules[spec.name] = tensor; spec.loader.exec_module(tensor)
    records = []
    with tempfile.TemporaryDirectory(prefix='metaflip-pocket-check-') as temporary:
        directory = Path(temporary)
        for i, ((shape, digest), body) in enumerate(cases.items()):
            name = f'{i}.txt'; (directory / name).write_bytes(body)
            records.append((directory, tensor.Record('x'.join(map(str, shape)), shape, body.count(b'\n'), name, digest)))
        if workers == 1:
            results = list(map(tensor._verify_one, records))
        else:
            with ProcessPoolExecutor(max_workers=workers, mp_context=multiprocessing.get_context('fork')) as pool:
                results = list(pool.map(tensor._verify_one, records))
    return dict(schema=1, complete=True, field='GF(2)', record_claim=False, cases=len(results),
        terms=sum(r.terms for r in results), pair_xors=sum(r.pair_xors for r in results),
        pocket_census=census, macro_transitions=transitions, image_space_pairs=checked_pairs,
        finite_join_pairs=pair_total, walk_attempts=walk_attempts, pocket_passes=pocket_summaries,
        results=[asdict(r) for r in results])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--workers', type=int, choices=range(1, 5), default=2)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = verify(args.root, args.workers)
    if args.report:
        args.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'results'}))
