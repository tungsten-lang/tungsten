#!/usr/bin/env python3
"""Independent dense simultaneous-map replay, including negative-scan sources."""
import argparse
from collections import Counter
from dataclasses import asdict
import hashlib
import json
from pathlib import Path
import tempfile

from verify_coordinate_projections import EDGES, project_grid, verify as verify_base
from verify_dual_projections import project_dual_grid
from verify_pair_reductions import replay as replay_pairs
from verify_representation_portfolio import contained, parse_terms
import verify_block_composition_records as tensor


def project_joint_grid(row, terms):
    shape, keep, duals = row['parent_shape'], row['keep'], row['duals']
    project_grid(shape, [], keep)
    assert isinstance(duals, list) and len(duals) == 2
    dimensions = [d['dimension'] for d in duals]
    assert all(type(d) is int and 0 <= d < 3 for d in dimensions)
    assert dimensions == sorted(set(dimensions))
    maps = {}
    for dual in duals:
        assert set(dual) == {'dimension', 'u', 'v'}
        d, u, v = (dual[k] for k in ('dimension', 'u', 'v'))
        n = shape[d]
        assert n >= 2 and len(keep[d]) == n-1
        assert all(type(x) is int and 0 < x < 2**n for x in (u, v))
        assert sum(((u >> j) & 1)*((v >> j) & 1) for j in range(n)) % 2 == 1
        pivot = next(j for j in range(n) if (u >> j) & 1)
        assert keep[d] == [j for j in range(n) if j != pivot]
        left = [[int(old == j) ^ (((u >> old) & 1)*int(j == pivot)) for j in range(n)] for old in keep[d]]
        right = [[int(old == j) ^ (((v >> old) & 1)*((u >> j) & 1)) for j in range(n)] for old in keep[d]]
        assert all(sum(a*b for a, b in zip(m, nr)) % 2 == int(i == j)
                   for i, m in enumerate(left) for j, nr in enumerate(right))
        affected = [axis for axis, edge in enumerate(EDGES) if d in edge]
        maps[affected[0], d], maps[affected[1], d] = left, right
    for d in set(range(3))-set(dimensions):
        assert keep[d] == list(range(shape[d]))
    changes = sum(not (dual['u'] == dual['v'] and dual['u'].bit_count() == 1) for dual in duals)
    assert row['control_kind'] == ('coordinate', 'single_dual', 'joint_dual')[changes]
    first_keep = [list(range(n)) for n in shape]
    first_keep[dimensions[0]] = keep[dimensions[0]]
    intermediate = project_dual_grid(dict(parent_shape=shape, keep=first_keep, dual=duals[0]), terms)
    assert type(row['intermediate_rank']) is int and row['intermediate_rank'] == len(intermediate)
    parity = Counter()
    for term in terms:
        transformed = []
        for axis, (word, (a, b)) in enumerate(zip(term, EDGES)):
            ma, mb = [maps.get((axis, d), [[int(old == j) for j in range(shape[d])]
                                          for old in keep[d]]) for d in (a, b)]
            value = 0
            for i, mr in enumerate(ma):
                for j, mc in enumerate(mb):
                    bit = sum(mr[x]*mc[y]*((word >> (x*shape[b]+y)) & 1)
                              for x in range(shape[a]) for y in range(shape[b])) % 2
                    value |= bit << (i*len(keep[b])+j)
            transformed.append(value)
        if all(transformed):
            parity[tuple(transformed)] += 1
    projected = sorted(t for t, c in parity.items() if c % 2)
    if 'raw_rank' in row:
        assert type(row['raw_rank']) is int and row['raw_rank'] == len(projected)
    if row.get('reduction_order') is not None:
        projected = replay_pairs(dict(shape=row['shape'], parent_shape=row['shape'],
            keep=[list(range(n)) for n in row['shape']], reduction_order=row['reduction_order'],
            reduction_trace=row['reduction_trace']), projected)
    else:
        assert not row.get('reduction_trace')
    return projected


def verify(root, workers=1):
    root = root.resolve()
    report = json.loads((root/'report.json').read_bytes())
    assert report['projection_kind'] == 'joint_canonical_dual_kernel'
    assert all(row['complete'] and row['views'] == row['planned_views'] for row in report['rows'])
    result = verify_base(root, workers, reconstruct=project_joint_grid)
    # A negative result must not evade verification of its source tensor.
    seen = set()
    with tempfile.TemporaryDirectory(prefix='metaflip-joint-source-check-') as folder:
        temp = Path(folder)
        for row in report['rows']:
            shape = tuple(row['parent_shape'])
            path = contained(root, row['parent_path'])
            raw = path.read_bytes()
            assert hashlib.sha256(raw).hexdigest() == row['parent_sha256']
            result['source_sha256'][row['parent_path']] = row['parent_sha256']
            key = shape, row['parent_sha256']
            if key in seen:
                continue
            seen.add(key)
            terms = parse_terms(raw, int(raw.splitlines()[0]))
            body = ''.join('R '+' '.join(map(str, t))+'\n' for t in terms).encode()
            digest = hashlib.sha256(body).hexdigest()
            if any(r['target'] == 'x'.join(map(str, shape)) and r['sha256'] == digest for r in result['results']):
                continue
            filename = f'{len(seen)}.txt'
            (temp/filename).write_bytes(body)
            checked = tensor._verify_one((temp, tensor.Record('x'.join(map(str, shape)), shape,
                                          len(terms), filename, digest)))
            result['results'].append(asdict(checked))
            result['tensors'] += 1
            result['terms'] += checked.terms
            result['pair_xors'] += checked.pair_xors
    result['projection_kind'] = report['projection_kind']
    result['selected_source_tensors_checked'] = len(seen)
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--workers', type=int, choices=(1, 2), default=1)
    a = p.parse_args()
    if a.output.exists():
        p.error('output must not exist')
    result = verify(a.root, a.workers)
    a.output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('source_sha256', 'results')}), flush=True)
