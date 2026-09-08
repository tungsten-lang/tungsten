#!/usr/bin/env python3
"""Independent dense-matrix reconstruction and full-tensor dual-map audit."""
import argparse
from collections import Counter
import json
from pathlib import Path

from verify_coordinate_projections import EDGES, project_grid, verify as verify_base


def project_dual_grid(row, terms):
    shape, keep, dual = row['parent_shape'], row['keep'], row['dual']
    project_grid(shape, [], keep)
    assert set(dual) == {'dimension', 'u', 'v'}
    dimension, u, v = (dual[key] for key in ('dimension', 'u', 'v'))
    assert type(dimension) is int and dimension in (0, 1, 2)
    n = shape[dimension]
    assert n >= 2 and len(keep[dimension]) == n-1
    assert all(type(value) is int and 0 < value < 2**n for value in (u, v))
    assert sum(((u >> j) & 1)*((v >> j) & 1) for j in range(n)) % 2 == 1
    pivot = next(j for j in range(n) if (u >> j) & 1)
    assert keep[dimension] == [j for j in range(n) if j != pivot]
    left = [[int(old == j) ^ (((u >> old) & 1)*int(j == pivot)) for j in range(n)]
            for old in keep[dimension]]
    right = [[int(old == j) ^ (((v >> old) & 1)*((u >> j) & 1)) for j in range(n)]
             for old in keep[dimension]]
    assert all(sum(a*b for a, b in zip(m, nrow)) % 2 == int(i == j)
               for i, m in enumerate(left) for j, nrow in enumerate(right))
    affected = [axis for axis, edge in enumerate(EDGES) if dimension in edge]
    # Retain the independently built dense matrices and their pairing check,
    # but expand only nonzero matrix entries inside the tensor loop.
    supports = []
    for axis, (a, b) in enumerate(EDGES):
        maps = [[[int(old == j) for j in range(shape[d])] for old in keep[d]] for d in (a, b)]
        if dimension in (a, b):
            maps[(a, b).index(dimension)] = left if axis == affected[0] else right
        supports.append([[tuple(j for j, value in enumerate(r) if value) for r in matrix] for matrix in maps])
    counts = Counter()
    for term in terms:
        mapped = []
        for axis, (word, (a, b)) in enumerate(zip(term, EDGES)):
            value = 0
            for i, mr in enumerate(supports[axis][0]):
                for j, mc in enumerate(supports[axis][1]):
                    bit = sum((word >> (x*shape[b]+y)) & 1 for x in mr for y in mc) % 2
                    value |= bit << (i*len(keep[b])+j)
            mapped.append(value)
        if all(mapped):
            counts[tuple(mapped)] += 1
    return sorted(term for term, count in counts.items() if count % 2)


def verify(root, workers=2):
    report = json.loads((root / 'report.json').read_bytes())
    assert report['projection_kind'] == 'canonical_dual_kernel'
    result = verify_base(root, workers, reconstruct=project_dual_grid)
    result['projection_kind'] = report['projection_kind']
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--workers', type=int, choices=range(1, 5), default=2)
    args = p.parse_args()
    assert not args.output.exists()
    result = verify(args.root, args.workers)
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('source_sha256', 'results')}), flush=True)
