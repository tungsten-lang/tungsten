#!/usr/bin/env python3
"""Independent shared-factor product maps, tensors, and matched join replay.

The finite parent/scale screen is a heuristic, not an optimal decomposition
certificate. Reference metadata does not certify global novelty.
"""
import argparse
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
from dataclasses import asdict
import hashlib
from itertools import product
import json
import math
import multiprocessing
from pathlib import Path
import tempfile

import verify_block_composition_records as tensor
from verify_cofactor_mergers import verify as verify_cofactor
from verify_representation_portfolio import contained, parse_terms

EDGES = ((0,1),(1,2),(0,2))


def positions(word):
    while word:
        bit = word & -word
        yield bit.bit_length()-1
        word ^= bit


def elementary(group):
    indices = group['indices']
    assert indices and all(type(i) is int and i >= 0 for i in indices)
    if 'elementary_shape' in group:
        assert 'axis' not in group
        shape = group['elementary_shape']
        assert len(shape) == 3 and all(type(d) is int and d > 0 for d in shape)
    else:
        axis = group.get('axis')
        assert axis is None or type(axis) is int and axis in range(3)
        assert axis is not None or len(indices) == 1
        shape = [1,1,1]
        if axis is not None:
            shape[(2,0,1)[axis]] = len(indices)
    assert math.prod(shape) == len(indices)
    return shape


def factor_maps(parent, group):
    shape = elementary(group)
    maps = [dict() for _ in range(3)]
    for index, coordinates in zip(group['indices'], product(*(range(d) for d in shape))):
        assert index < len(parent)
        for axis, (r,c) in enumerate(EDGES):
            key = coordinates[r], coordinates[c]
            assert maps[axis].get(key, parent[index][axis]) == parent[index][axis]
            maps[axis][key] = parent[index][axis]
    return shape, maps


def expand_group(parent_shape, parent, scale, group, leaf_shape, leaf):
    shape, maps = factor_maps(parent, group)
    assert leaf_shape == [d*s for d,s in zip(shape, scale)]
    # Build sparse coordinate substitution tables, then linearly substitute
    # each factor. This does not call the Ruby constructor or tensor checker.
    transforms = []
    for axis, (r,c) in enumerate(EDGES):
        images = {}
        for (i,j), outer in maps[axis].items():
            for u,v in product(range(scale[r]),range(scale[c])):
                source = (i*scale[r]+u)*leaf_shape[c]+j*scale[c]+v
                image = 0
                for bit in positions(outer):
                    a,b = divmod(bit,parent_shape[c])
                    image ^= 1 << ((a*scale[r]+u)*(parent_shape[c]*scale[c])+b*scale[c]+v)
                images[source] = image
        transforms.append(images)
    for term in leaf:
        out = []
        for axis, word in enumerate(term):
            value = 0
            for bit in positions(word):
                value ^= transforms[axis][bit]
            out.append(value)
        if all(out):
            yield tuple(out)


def verify_products(root, outputs, baseline, workers=2):
    root = root.resolve()
    read = lambda path: json.loads(path.read_text())
    tensors = {}
    def load(base, entry):
        shape = entry['shape']
        assert len(shape) == 3 and all(type(d) is int and 1 <= d <= 32 for d in shape)
        raw = contained(base,entry['path']).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == entry['sha256']
        terms = parse_terms(raw, int(raw.splitlines()[0]))
        assert all(len(t)==3 and all(type(v) is int and 0 < v < 1 << (shape[r]*shape[c])
                   for v,(r,c) in zip(t,EDGES)) for t in terms)
        body = ''.join('R '+' '.join(map(str,t))+'\n' for t in terms).encode()
        tensors[tuple(shape),hashlib.sha256(body).hexdigest()] = body
        return terms
    assert baseline['complete'] and baseline['field'] == 'GF(2)' and not baseline['record_claim']
    ranks = {tuple(row['shape']):row['augmented_rank'] for row in baseline['rows']}
    seen = set()
    for row in outputs:
        path = contained(root,row['recipe'])
        recipe = read(path)
        assert recipe['schema'] in (1,2) and recipe['field'] == 'GF(2)' and not recipe['record_claim']
        parent = load(path.parent,recipe['parent'])
        scale = recipe['scale']
        assert len(scale)==3 and all(type(d) is int and d > 0 for d in scale)
        assert sorted(i for g in recipe['groups'] for i in g['indices']) == list(range(len(parent)))
        total = Counter()
        formula = 0
        for group in recipe['groups']:
            assert recipe['schema'] == 2 or 'elementary_shape' not in group
            leaf = load(path.parent,group['leaf'])
            formula += len(leaf)
            total.update(expand_group(recipe['parent']['shape'],parent,scale,group,group['leaf']['shape'],leaf))
        final = load(path.parent,recipe['result'])
        assert sorted(t for t,n in total.items() if n % 2) == sorted(final), 'bud substitution mismatch'
        target = [d*s for d,s in zip(recipe['parent']['shape'],scale)]
        assert target == recipe['result']['shape'] and sorted(target) == row['target']
        assert formula == recipe['formula_rank'] == row['formula']
        assert len(final) == recipe['exact_rank'] == row['rank'] <= formula
        assert sum(v.bit_count() for t in final for v in t) == row['density']
        assert row['baseline'] == ranks[tuple(sorted(target))]
        assert row['gain'] == row['baseline']-row['formula'] > 0
        assert tuple(row['target']) not in seen
        seen.add(tuple(row['target']))
        print(json.dumps(dict(replayed=row['target'],rank=len(final))),flush=True)
    assert len(seen) == len(outputs)
    with tempfile.TemporaryDirectory(prefix='metaflip-bud-renewal-verify-') as directory:
        tmp = Path(directory)
        jobs = []
        for i,((shape,digest),body) in enumerate(tensors.items()):
            name=f'{i}.txt'
            (tmp/name).write_bytes(body)
            jobs.append((tmp,tensor.Record('x'.join(map(str,shape)),shape,len(body.splitlines()),name,digest)))
        if workers == 1:
            checks = list(map(tensor._verify_one,jobs))
        else:
            with ProcessPoolExecutor(max_workers=workers,mp_context=multiprocessing.get_context('fork')) as pool:
                checks = list(pool.map(tensor._verify_one,jobs))
    return dict(schema=1,complete=True,field='GF(2)',record_claim=False,
                products=len(seen),tensors=len(checks),terms=sum(c.terms for c in checks),
                pair_xors=sum(c.pair_xors for c in checks),
                heuristic_screen_not_optimality=True,results=[asdict(c) for c in checks])


def verify(root, workers=2):
    root = root.resolve()
    read = lambda path: json.loads(path.read_text())
    report = read(root/'report.json')
    assert report['kind'] == 'bud-renewal' and report['complete']
    assert report['field'] == 'GF(2)' and report['record_claim'] is False
    assert report['redistribution_cleared'] is False
    for name,digest in report['retained_files'].items():
        assert hashlib.sha256(contained(root,name).read_bytes()).hexdigest() == digest, name
    assert len(report['outputs']) == report['materialized_targets']
    result = verify_products(root, report['outputs'], read(root/'baseline-grid.json'), workers)
    post = verify_cofactor(contained(root,report['postcompression']),workers)
    assert post['totals']['compression_assessments_replayed'] == 103
    result['postcompression'] = {k:v for k,v in post.items() if k!='results'}
    return result


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--workers',type=int,choices=range(1,5),default=2)
    parser.add_argument('--report',type=Path)
    args=parser.parse_args()
    result=verify(args.root,args.workers)
    if args.report:
        args.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('results','postcompression')}))
