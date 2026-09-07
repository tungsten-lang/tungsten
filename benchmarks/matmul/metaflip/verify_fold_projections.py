#!/usr/bin/env python3
"""Dense-grid replay of paired coordinate/fold projections and full tensors."""
import argparse
from collections import Counter
import json
from pathlib import Path

from verify_coordinate_projections import EDGES, project_grid, verify as verify_base


def project_fold_grid(row, terms):
    shape, keep, fold = row['parent_shape'], row['keep'], row.get('fold')
    project_grid(shape, [], keep)  # Validate every coordinate, including plain controls.
    if fold is None:
        return project_grid(shape, terms, keep)
    assert set(fold) == {'dimension', 'factor', 'mask'}
    dimension, factor, mask = (fold[k] for k in ('dimension', 'factor', 'mask'))
    assert type(dimension) is int and dimension in (0, 1, 2)
    assert type(factor) is int and factor in (0, 1, 2) and dimension in EDGES[factor]
    assert len(keep[dimension]) == shape[dimension]-1
    assert type(mask) is int and 0 <= mask < 1 << len(keep[dimension])
    drop, = set(range(shape[dimension]))-set(keep[dimension])
    # The two maps of a shared tensor coordinate satisfy M*N^T = I.
    folded = [(1 << old) ^ (((mask >> i) & 1) << drop) for i, old in enumerate(keep[dimension])]
    coordinate = [1 << old for old in keep[dimension]]
    assert all((left & right).bit_count() % 2 == (i == j)
               for i, left in enumerate(folded) for j, right in enumerate(coordinate))
    counts = Counter()
    for term in terms:
        mapped = []
        for axis, (word, (a, b)) in enumerate(zip(term, EDGES)):
            value = 0
            for i, old_i in enumerate(keep[a]):
                for j, old_j in enumerate(keep[b]):
                    bit = (word >> (old_i*shape[b]+old_j)) & 1
                    if axis == factor and a == dimension and (mask >> i) & 1:
                        bit ^= (word >> (drop*shape[b]+old_j)) & 1
                    if axis == factor and b == dimension and (mask >> j) & 1:
                        bit ^= (word >> (old_i*shape[b]+drop)) & 1
                    value |= bit << (i*len(keep[b])+j)
            mapped.append(value)
        if all(mapped):
            counts[tuple(mapped)] += 1
    return sorted(term for term, count in counts.items() if count % 2)


def verify(root, workers=2):
    report = json.loads((root / 'report.json').read_bytes())
    assert report['projection_kind'] == 'coordinate_or_one_sided_fold'
    result = verify_base(root, workers, reconstruct=project_fold_grid)
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
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('source_sha256', 'results')}), flush=True)
