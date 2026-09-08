#!/usr/bin/env python3
"""Replay saved mixed parent covers against a frozen constructive price plan.

Checks literal source identity/order, whole GF(2) tensors, exact factor maps,
complete term partitions, and every reported formula/ordinary-cover cost.
Does not certify optimizer optimality, price-plan leaves, or record novelty.
"""
import argparse
from collections import Counter
from dataclasses import asdict
from functools import lru_cache
import hashlib
from itertools import product
import json
from pathlib import Path
import tempfile

import verify_block_composition_records as tensor
from verify_bud_renewal import factor_maps
from verify_representation_portfolio import contained, parse_terms


def verify(root, inputs_path, plan_path):
    root, inputs_path, plan_path = map(lambda p: Path(p).resolve(), (root, inputs_path, plan_path))
    blobs = [p.read_bytes() for p in (root/'report.json', inputs_path, plan_path)]
    report, inputs, plan = map(json.loads, blobs)
    for document in (report, inputs, plan):
        assert document['complete'] is True and document['field'] == 'GF(2)' and document['record_claim'] is False
    # This scan format has exactly one corpus and one frozen plan pin. They
    # retain historical names when copied; do not require their old locations.
    for suffix, blob in (('/inputs.json', blobs[1]), ('/report.json', blobs[2])):
        matches = [v for k, v in report['source_sha256'].items() if k.endswith(suffix)]
        assert matches == [hashlib.sha256(blob).hexdigest()]
    assert len(plan['model_shapes']) == len(plan['baseline_recipes'])
    prices = {tuple(s): r['rank'] for s, r in zip(plan['model_shapes'], plan['baseline_recipes'])}
    assert len(prices) == len(plan['model_shapes'])
    assert all(len(s) == 3 and tuple(sorted(s)) == s and all(type(d) is int and 1 <= d <= 32 for d in s)
               and type(v) is int and v > 0 for s, v in prices.items())
    maximum = report['limits']['max_leaf']
    assert type(maximum) is int and 2 <= maximum <= 32
    assert report['parents'] and report['rows']
    pins, cases, parents, cover_hashes = {}, {}, {}, []

    def source(entry, prior):
        shape = entry['shape']
        assert shape == prior['shape'] and len(shape) == 3
        assert all(type(d) is int and 1 <= d <= maximum for d in shape)
        path = contained(root, entry['path'])
        body = path.read_bytes()
        assert hashlib.sha256(body).hexdigest() == entry['sha256']
        pins[entry['path']] = entry['sha256']
        terms = parse_terms(body, entry['rank'])
        assert len(terms) == entry['rank'] == prior['rank'] and len(set(terms)) == len(terms)
        # The corpus file fixes term indices, not just an unordered identity.
        if entry['sha256'] != prior['sha256']:
            old_path = Path(prior['path']).resolve()
            old = old_path.read_bytes()
            assert hashlib.sha256(old).hexdigest() == prior['sha256']
            assert terms == parse_terms(old, prior['rank'])
        canonical = 'x'.join(map(str, shape))+'\n'+''.join(' '.join(map(str, t))+'\n' for t in sorted(terms))
        assert hashlib.sha256(canonical.encode()).hexdigest() == prior['identity']
        check = ''.join('R '+' '.join(map(str, t))+'\n' for t in terms).encode()
        cases[tuple(shape), hashlib.sha256(check).hexdigest()] = check
        return terms

    for parent in report['parents']:
        index = parent['index']
        assert type(index) is int and 0 <= index < len(inputs['parents']) and index not in parents
        prior = inputs['parents'][index]
        assert parent['identity'] == prior['identity']
        assert parent['rank'] == parent['source']['rank'] and parent['shape'] == prior['shape']
        assert parent['prior_mixed_partitions'] == len(prior.get('mixed_partitions', []))
        terms = source(parent['source'], prior)
        shapes = []
        for i, groups in enumerate(parent['covers']):
            assert groups and sorted(j for g in groups for j in g['indices']) == list(range(len(terms)))
            dims = []
            for group in groups:
                assert set(group) in ({'axis', 'indices'}, {'elementary_shape', 'indices'})
                dim, _ = factor_maps(terms, group)
                dims.append(tuple(dim))
            shapes.append(tuple(Counter(dims).items()))
            cover_hashes.append(dict(parent=index, cover=i, sha256=hashlib.sha256(
                json.dumps(groups, sort_keys=True, separators=(',', ':')).encode()).hexdigest()))
        signatures = tuple(tuple(Counter(t[a] for t in terms).values()) for a in range(3))
        parents[index] = dict(shape=parent['shape'], rank=len(terms), signatures=signatures, covers=shapes)

    @lru_cache(None)
    def bucket_prices(scale, axis, rank):
        free = (2, 0, 1)[axis]
        leaf_costs = []
        for k in range(1, min(rank, maximum//scale[free])+1):
            leaf = list(scale); leaf[free] *= k
            leaf_costs.append(prices[tuple(sorted(leaf))])
        dp = [0]
        for k in range(1, rank+1):
            dp.append(min(dp[k-j]+leaf_costs[j-1] for j in range(1, min(k, len(leaf_costs))+1)))
        return dp

    seen = set()
    for row in report['rows']:
        index = row['parent']
        assert type(index) is int
        parent = parents[index]
        scale = tuple(row['scale'])
        assert len(scale) == 3 and all(type(d) is int and d > 0 for d in scale)
        target = sorted(d*k for d, k in zip(parent['shape'], scale))
        assert max(target) <= maximum and target == row['target']
        assert all(type(row[k]) is int and row[k] > 0 for k in ('local_rank', 'pure_rank'))
        assert (index, scale) not in seen
        seen.add((index, scale))
        assert row['local_rank'] == prices[tuple(target)]
        pure = min(sum(bucket_prices(scale, a, parent['rank'])[k] for k in sig)
                   for a, sig in enumerate(parent['signatures']))
        assert row['pure_rank'] == pure
        if row.get('timed_out'):
            assert row['timed_out'] is True and row['improved'] is False
            assert not any(k in row for k in ('cover', 'packing', 'rank'))
            continue
        cover = row['cover']
        assert type(cover) is int and 0 <= cover < len(parent['covers'])
        assert type(row['rank']) is int and type(row['packing']['exact_within_model']) is bool
        value = 0
        for dims, count in parent['covers'][cover]:
            leaf = tuple(sorted(d*k for d, k in zip(dims, scale)))
            assert max(leaf) <= maximum
            value += count*prices[leaf]
        assert value == row['rank'] == row['packing']['formula_rank'] <= pure
        assert row['improved'] is (value < row['local_rank'])
        assert row['packing']['record_claim'] is False
    assert report['direct_improvements'] == [r for r in report['rows'] if r['improved']]
    assert all(type(report[k]) is int and report[k] > 0 for k in ('requested_parents', 'requested_cases'))
    assert all(type(report[k]) is bool for k in ('all_cases_attempted', 'all_exact_within_model'))
    assert len(parents) <= report['requested_parents'] and len(seen) <= report['requested_cases']
    families = report.get('selection', {}).get('families')
    if families is not None:
        # New reusable-producer format: independently bind "all" and the
        # declared heuristic sample to the entire frozen input corpus.
        assert isinstance(families, list) and families
        family_shapes, selected = set(), set()
        for family in families:
            shape = tuple(family['shape'])
            assert len(shape) == 3 and all(type(d) is int and 1 <= d <= maximum for d in shape)
            assert shape not in family_shapes and type(family['sampling_only']) is bool
            family_shapes.add(shape)
            members = [(i,p) for i,p in enumerate(inputs['parents']) if tuple(p['shape']) == shape]
            assert members and type(family['family_parents']) is int and family['family_parents'] == len(members)
            if family['sampling_only']:
                latest = {json.dumps(p['signature'], separators=(',', ':')): i for i,p in members}
                picked = set(latest.values()) | {i for i,p in members if p.get('mixed_partitions', [])}
            else:
                picked = {i for i,p in members}
            assert type(family['selected_parents']) is int and family['selected_parents'] == len(picked)
            selected.update(picked)
        expected_parents = sorted(selected)
        assert report['requested_parents'] == len(expected_parents)
        expected_cases = sum((maximum//inputs['parents'][i]['shape'][0]) *
                             (maximum//inputs['parents'][i]['shape'][1]) *
                             (maximum//inputs['parents'][i]['shape'][2]) for i in expected_parents)
        assert report['requested_cases'] == expected_cases
        assert list(parents) == expected_parents[:len(parents)]
    assert report['all_cases_attempted'] is (len(seen) == report['requested_cases'])
    producer_exact = report['all_cases_attempted'] and all(r.get('packing', {}).get('exact_within_model') for r in report['rows'])
    assert report['all_exact_within_model'] == producer_exact
    if report['all_cases_attempted']:
        expected = {(i, s) for i, p in parents.items()
                    for s in product(*(range(1, maximum//d+1) for d in p['shape']))}
        assert len(parents) == report['requested_parents'] and seen == expected
    checked = []
    with tempfile.TemporaryDirectory(prefix='metaflip-cover-audit-') as directory:
        tmp = Path(directory)
        for i, ((shape, digest), body) in enumerate(cases.items()):
            name = f'{i}.txt'; (tmp/name).write_bytes(body)
            checked.append(asdict(tensor._verify_one((tmp, tensor.Record(
                'x'.join(map(str, shape)), shape, len(body.splitlines()), name, digest)))))
    assert [p.read_bytes() for p in (root/'report.json', inputs_path, plan_path)] == blobs
    assert all(hashlib.sha256(contained(root, p).read_bytes()).hexdigest() == h for p, h in pins.items())
    return dict(complete=True, field='GF(2)', record_claim=False,
                products_materialized=False, search_optimality_certified=False, price_plan_leaves_reverified=False,
                family_selection_verified=families is not None,
                report_sha256=hashlib.sha256(blobs[0]).hexdigest(), inputs_sha256=hashlib.sha256(blobs[1]).hexdigest(),
                price_plan_sha256=hashlib.sha256(blobs[2]).hexdigest(), source_sha256=pins,
                parents=len(parents), cases=len(seen), covers=cover_hashes, tensors=len(checked),
                terms=sum(r['terms'] for r in checked), pair_xors=sum(r['pair_xors'] for r in checked),
                results=checked, improved_shapes=sorted({tuple(r['target']) for r in report['direct_improvements']}))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--inputs', type=Path, required=True)
    parser.add_argument('--price-plan', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('output must not exist')
    result = verify(args.root, args.inputs, args.price_plan)
    with args.output.open('x') as stream:
        stream.write(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('source_sha256', 'results', 'covers')}))
