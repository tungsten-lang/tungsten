#!/usr/bin/env python3
"""Independent bit-grid projection, sort/group cleanup and full tensor audit."""
import argparse
import json
from pathlib import Path

from verify_coordinate_projections import project_grid, verify as verify_base
from verify_pair_reductions import replay as replay_pairs


def project_reduced_grid(row,terms):
    projected=project_grid(row['parent_shape'],terms,row['keep'])
    assert tuple(map(len,row['keep']))==tuple(row['shape'])
    assert type(row['raw_rank']) is int and row['raw_rank']==len(projected)
    return replay_pairs(dict(shape=row['shape'],parent_shape=row['shape'],
        keep=[list(range(n)) for n in row['shape']],reduction_order=row['reduction_order'],
        reduction_trace=row['reduction_trace']),projected)


def verify(root,workers=1):
    root=Path(root).resolve()
    report=json.loads((root/'report.json').read_bytes())
    assert report['projection_kind']=='coordinate_then_shared_pair_reduction'
    order=report['limits']['pair_order']
    assert len(order)==3 and all(type(i) is int for i in order) and sorted(order)==[0,1,2]
    assert all(row['reduction_order']==order for row in report['outputs'])
    result=verify_base(root,workers,reconstruct=project_reduced_grid)
    result['projection_kind']=report['projection_kind']
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--workers',type=int,choices=range(1,5),default=1)
    args=parser.parse_args()
    if args.output.exists():parser.error('output must not exist')
    result=verify(args.root,args.workers)
    with args.output.open('x') as stream:stream.write(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('source_sha256','results')}),flush=True)
