#!/usr/bin/env python3
"""Finite zero-padding upper bounds, with the same correction to references.

Restriction gives R(a,b,c) <= R(A,B,C) for componentwise larger dimensions.
This module preserves the original supplying shape, not a circular price-only
recipe. It screens a frozen table; it neither verifies its source witnesses nor
admits an expanded tensor or certifies a world record.
"""
import argparse
import hashlib
from itertools import combinations_with_replacement
import json
from math import prod
from pathlib import Path


def domain(prices):
    if not prices:
        raise ValueError('empty price table')
    for shape,rank in prices.items():
        if (not isinstance(shape,tuple) or len(shape)!=3 or
                any(type(n) is not int or not 1<=n<=32 for n in shape) or
                shape!=tuple(sorted(shape)) or type(rank) is not int or rank<=0):
            raise ValueError('invalid canonical shape or rank')
    maximum=max(s[-1] for s in prices)
    expected=set(combinations_with_replacement(range(1,maximum+1),3))
    if set(prices)!=expected:
        raise ValueError('complete canonical dimension grid required')
    return maximum


def successors(shape,maximum):
    for axis,n in enumerate(shape):
        if n<maximum:
            target=list(shape);target[axis]+=1
            yield tuple(sorted(target))


def restriction_envelope(prices):
    maximum=domain(prices)
    result={s:(r,s) for s,r in prices.items()}
    for shape in sorted(prices,key=lambda s:(prod(s),s),reverse=True):
        for larger in successors(shape,maximum):
            if result[larger][0]<result[shape][0]:
                result[shape]=result[larger]
    verify_envelope(prices,result)
    return result


def verify_envelope(prices,result):
    """Check supplying roots plus Bellman equalities on the finite acyclic grid."""
    maximum=domain(prices)
    if result.keys()!=prices.keys():
        raise ValueError('envelope domain mismatch')
    for shape,(rank,source) in result.items():
        if (source not in prices or any(a>b for a,b in zip(shape,source)) or
                type(rank) is not int or rank!=prices[source] or rank>prices[shape]):
            raise ValueError('invalid restriction witness root')
        bound=min([prices[shape]]+[result[s][0] for s in successors(shape,maximum)])
        if rank!=bound:
            raise ValueError('incomplete finite restriction envelope')


def plan_prices(plan):
    if (plan.get('complete') is not True or plan.get('field')!='GF(2)' or
            plan.get('record_claim') is not False):
        raise ValueError('expected sealed unconditional GF(2) price plan')
    shapes,recipes=plan['model_shapes'],plan['baseline_recipes']
    if len(shapes)!=len(recipes) or len({tuple(s) for s in shapes})!=len(shapes):
        raise ValueError('shape/recipe mismatch')
    prices={tuple(s):r['rank'] for s,r in zip(shapes,recipes)}
    domain(prices)
    return prices


def screen(plan,reference=None):
    prices=plan_prices(plan);closed=restriction_envelope(prices)
    refs=ref_closed=None
    if reference is not None:
        if reference.get('complete') is not True or reference.get('record_claim') is not False:
            raise ValueError('unsealed reference screen')
        refs={tuple(row['shape']):row['reference'] for row in reference['rows']}
        if len(refs)!=len(reference['rows']) or refs.keys()!=prices.keys():
            raise ValueError('reference domain mismatch')
        ref_closed=restriction_envelope(refs)
    rows=[]
    for shape in sorted(prices):
        rank,source=closed[shape]
        row=dict(shape=shape,rank=rank,raw_rank=prices[shape],source_shape=source,
                 improved_price=rank<prices[shape])
        if refs is not None:
            bound,ref_source=ref_closed[shape]
            row.update(reference=bound,raw_reference=refs[shape],reference_source_shape=ref_source,
                below_reference=rank<bound,new_crossing=rank<bound and prices[shape]>=bound)
        rows.append(row)
    return dict(complete=True,field='GF(2)',record_claim=False,screen_only=True,
        constructive_sources_reverified=False,finite_envelope_checked=True,
        scope='Exact upper-bound propagation on the supplied complete dimension grid; not tensor-rank optimality or novelty.',
        reference_policy='The supplied comparison metadata is also closed under restriction; field applicability is not strengthened.',
        shapes=len(rows),improved_prices=sum(r['improved_price'] for r in rows),
        reference_improvements=0 if refs is None else sum(ref_closed[s][0]<refs[s] for s in refs),
        below_reference=None if refs is None else sum(r['below_reference'] for r in rows),
        new_reference_crossings=[] if refs is None else [r for r in rows if r['new_crossing']],rows=rows)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan',type=Path,required=True)
    parser.add_argument('--reference',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():parser.error('output must not exist')
    paths=[args.plan,Path(__file__)]+([args.reference] if args.reference else [])
    blobs={p.resolve():p.read_bytes() for p in paths}
    result=screen(json.loads(blobs[args.plan.resolve()]),
                  json.loads(blobs[args.reference.resolve()]) if args.reference else None)
    if any(p.read_bytes()!=raw for p,raw in blobs.items()):
        raise ValueError('source changed during screen')
    result['source_sha256']={str(p):hashlib.sha256(raw).hexdigest() for p,raw in blobs.items()}
    with args.output.open('x') as stream:stream.write(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('rows','source_sha256')}))
