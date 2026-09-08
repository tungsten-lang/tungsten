#!/usr/bin/env python3
"""Independent dense fold, sort/group cleanup, then full GF(2) tensor replay."""
import argparse
import json
from pathlib import Path

from verify_coordinate_projections import verify as verify_base
from verify_fold_projections import project_fold_grid
from verify_pair_reductions import replay as replay_pairs


def project_reduced_fold(row, terms):
    child = project_fold_grid(row, terms)
    assert type(row['raw_rank']) is int and row['raw_rank'] == len(child)
    return replay_pairs(dict(shape=row['shape'], parent_shape=row['shape'],
        keep=[list(range(n)) for n in row['shape']], reduction_order=row['reduction_order'],
        reduction_trace=row['reduction_trace']), child)


def verify(root, workers=1):
    root = Path(root).resolve()
    report = json.loads((root/'report.json').read_bytes())
    assert report['projection_kind'] == 'bounded_fold_then_shared_pair_reduction'
    limits = report['limits']; order = limits['pair_order']; weight = limits['max_mask_weight']
    assert type(weight) is int and 0 <= weight <= 3
    assert len(order) == 3 and all(type(i) is int for i in order) and sorted(order) == [0, 1, 2]
    for row in report['outputs']:
        assert row['reduction_order'] == order
        if row['fold'] is not None:
            mask = row['fold']['mask']
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
