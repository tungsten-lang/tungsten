#!/usr/bin/env python3
"""Sort/group replay of shared-pair cleanup, followed by full tensor checks."""
import argparse
from functools import reduce
from itertools import groupby
import json
from operator import xor
from pathlib import Path

from verify_coordinate_projections import verify as verify_base


def replay(row, terms):
    assert row['shape'] == row['parent_shape']
    assert row['keep'] == [list(range(n)) for n in row['shape']]
    order = row['reduction_order']
    assert len(order) == 3 and all(type(i) is int for i in order) and sorted(order) == [0, 1, 2]
    terms, trace = sorted(terms), []
    while True:
        before_cycle = len(terms)
        for axis in order:
            key = lambda term: tuple(term[j] for j in range(3) if j != axis)
            child = []
            for _, group in groupby(sorted(terms, key=key), key=key):
                block = list(group)
                value = reduce(xor, (term[axis] for term in block), 0)
                if value:
                    term = list(block[0]); term[axis] = value
                    child.append(tuple(term))
            if len(child) < len(terms):
                trace.append(dict(axis=axis, before=len(terms), after=len(child)))
            assert len(child) <= len(terms)
            terms = sorted(child)
        if len(terms) == before_cycle:
            break
    assert trace == row['reduction_trace']
    return terms


def verify(root, workers=2):
    report = json.loads((root/'report.json').read_bytes())
    assert report['projection_kind'] == 'shared_pair_reduction'
    result = verify_base(root, workers, reconstruct=replay)
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
