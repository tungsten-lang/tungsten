#!/usr/bin/env python3
"""Independent dense fold, sort/group cleanup, then full GF(2) tensor replay."""
import argparse
import json
from pathlib import Path

from verify_coordinate_projections import project_grid, verify as verify_base
from verify_fold_projections import project_fold_grid
from verify_pair_reductions import replay as replay_pairs


def project_joint_fold_grid(row, terms):
    shape, keep, folds = row['parent_shape'], row['keep'], row['folds']
    project_grid(shape, [], keep)
    assert all(n-len(k) in (0, 1) for n, k in zip(shape, keep))
    assert isinstance(folds, list) and len(folds) <= 3
    by_dimension = {}
    for fold in folds:
        assert set(fold) == {'dimension', 'factor', 'mask'}
        dimension = fold['dimension']
        assert type(dimension) is int and dimension in (0, 1, 2) and dimension not in by_dimension
        assert len(keep[dimension]) == shape[dimension]-1
        by_dimension[dimension] = fold
    if all(n == len(k) for n, k in zip(shape, keep)):
        return project_grid(shape, terms, keep)
    current, child = list(shape), terms
    for dimension in range(3):
        if len(keep[dimension]) == shape[dimension]: continue
        coords = [list(range(n)) for n in current]
        coords[dimension] = keep[dimension]
        child = project_fold_grid(dict(parent_shape=current, keep=coords, fold=by_dimension.get(dimension)), child)
        current[dimension] = len(keep[dimension])
    return sorted(child)


def project_reduced_fold(row, terms):
    child = project_joint_fold_grid(row, terms) if 'folds' in row else project_fold_grid(row, terms)
    assert type(row['raw_rank']) is int and row['raw_rank'] == len(child)
    return replay_pairs(dict(shape=row['shape'], parent_shape=row['shape'],
        keep=[list(range(n)) for n in row['shape']], reduction_order=row['reduction_order'],
        reduction_trace=row['reduction_trace']), child)


def verify(root, workers=1):
    root = Path(root).resolve()
    report = json.loads((root/'report.json').read_bytes())
    assert report['projection_kind'] in ('bounded_fold_then_shared_pair_reduction',
                                        'bounded_joint_fold_then_shared_pair_reduction')
    joint = report['projection_kind'] == 'bounded_joint_fold_then_shared_pair_reduction'
    limits = report['limits']; order = limits['pair_order']; weight = limits['max_mask_weight']
    assert type(weight) is int and 0 <= weight <= 3
    assert len(order) == 3 and all(type(i) is int for i in order) and sorted(order) == [0, 1, 2]
    axes = limits['max_folded_axes'] if joint else 1
    assert type(axes) is int and axes in (1, 2, 3)
    for row in report['outputs']:
        assert row['reduction_order'] == order
        if joint:
            assert 'fold' not in row and isinstance(row['folds'], list) and len(row['folds']) <= axes
            folds = row['folds']
        else:
            assert 'folds' not in row
            folds = [] if row['fold'] is None else [row['fold']]
        for fold in folds:
            mask = fold['mask']
            assert type(mask) is int and mask > 0 and mask.bit_count() <= weight
    result = verify_base(root, workers, reconstruct=project_reduced_fold)
    result['projection_kind'] = report['projection_kind']
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--workers', type=int, choices=range(1, 5), default=1)
    a = p.parse_args()
    if a.output.exists(): p.error('output must not exist')
    result = verify(a.root, a.workers)
    with a.output.open('x') as stream: stream.write(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k: v for k, v in result.items() if k not in ('source_sha256', 'results')}), flush=True)
