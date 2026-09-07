#!/usr/bin/env python3
"""Independent reconstruction and full tensor audit of composition outputs."""
import argparse
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
from dataclasses import asdict
import hashlib
from itertools import permutations, product
import json
import multiprocessing
from pathlib import Path
import tempfile

import verify_block_composition_records as tensor
from verify_bud_renewal import expand_group, positions
from verify_representation_portfolio import contained, parse_terms

EDGES=((0,1),(1,2),(0,2))


def orient(terms, shape, target):
    permutation=next(p for p in permutations(range(3)) if [shape[j] for j in p]==list(target))
    out=[]
    for term in terms:
        values=[]
        for a,b in EDGES:
            x,y=permutation[a],permutation[b]
            source=EDGES.index(tuple(sorted((x,y))))
            value=term[source]
            if x>y:
                transposed=0
                for bit in positions(value):
                    i,j=divmod(bit,shape[x])
                    transposed ^= 1 << (j*shape[y]+i)
                value=transposed
            values.append(value)
        out.append(tuple(values))
    return sorted(out)


def embed(terms, shape, target, offsets):
    for term in terms:
        values=[]
        for word,(a,b) in zip(term,EDGES):
            value=0
            for bit in positions(word):
                i,j=divmod(bit,shape[b])
                value ^= 1 << ((i+offsets[a])*target[b]+j+offsets[b])
            values.append(value)
        yield tuple(values)


def kronecker(left, left_shape, right, right_shape):
    for l,r in product(left,right):
        values=[]
        for x,y,(a,b) in zip(l,r,EDGES):
            value=0
            for bit_x,bit_y in product(positions(x),positions(y)):
                i,j=divmod(bit_x,left_shape[b]);u,v=divmod(bit_y,right_shape[b])
                value ^= 1 << ((i*right_shape[a]+u)*(left_shape[b]*right_shape[b])+j*right_shape[b]+v)
            values.append(value)
        yield tuple(values)


def verify(root,workers=2):
    raw=(root/'report.json').read_bytes();report=json.loads(raw)
    assert report['complete'] and report['field']=='GF(2)' and not report['record_claim']
    cases={};pins={}
    def load(base,entry):
        path=contained(base,entry['path']);raw=path.read_bytes();digest=hashlib.sha256(raw).hexdigest()
        assert digest==entry['sha256'],path
        shape=tuple(entry['shape']);terms=parse_terms(raw,int(raw.splitlines()[0]))
        assert all(1<=n<=32 for n in shape)
        assert all(all(0<v<1<<(shape[a]*shape[b]) for v,(a,b) in zip(t,EDGES)) for t in terms)
        body=''.join('R '+' '.join(map(str,t))+'\n' for t in terms).encode()
        cases[shape,hashlib.sha256(body).hexdigest()]=body
        pins[str(path.relative_to(root.resolve()))]=digest
        return shape,terms
    for entry in report['tensors']:load(root,entry)
    bud_count=0
    for row in report['recipes']:
        target,actual=load(root,row['result']);assert list(target)==row['shape']
        assert len(actual)==row['rank']<=row['planned_rank']
        kind=row['kind']
        if kind in ('bud', 'mixed_bud'):
            path=contained(root,row['recipe']);raw_recipe=path.read_bytes();recipe=json.loads(raw_recipe)
            pins[str(path.relative_to(root))]=hashlib.sha256(raw_recipe).hexdigest()
            assert recipe['schema'] in (1,2) and recipe['field']=='GF(2)' and not recipe['record_claim']
            parent_shape,parent=load(path.parent,recipe['parent']);scale=recipe['scale']
            assert len(scale)==3 and all(type(n)is int and n>0 for n in scale)
            assert sorted(j for g in recipe['groups'] for j in g['indices'])==list(range(len(parent)))
            sums=Counter();formula=0
            for group in recipe['groups']:
                assert recipe['schema']==2 or 'elementary_shape' not in group
                leaf_shape,leaf=load(path.parent,group['leaf']);formula+=len(leaf)
                sums.update(expand_group(parent_shape,parent,scale,group,list(leaf_shape),leaf))
            source_shape,saved=load(path.parent,recipe['result'])
            assert source_shape==tuple(n*s for n,s in zip(parent_shape,scale))
            rebuilt=sorted(t for t,n in sums.items() if n%2)
            assert rebuilt==sorted(saved) and formula==recipe['formula_rank']
            assert len(saved)==recipe['exact_rank']
            expected=orient(saved,source_shape,target);bud_count+=1
        elif kind=='block':
            (left_shape,left),(right_shape,right)=[load(root,e) for e in row['inputs']]
            axis,cut=row['axis'],row['cut'];assert 0<=axis<3 and 0<cut<target[axis]
            assert all(left_shape[a]==right_shape[a]==target[a] for a in range(3) if a!=axis)
            assert left_shape[axis]==cut and right_shape[axis]==target[axis]-cut
            offsets=[0,0,0];offsets[axis]=cut
            expected=sorted(list(embed(left,left_shape,target,[0,0,0]))+
                            list(embed(right,right_shape,target,offsets)))
        elif kind=='kronecker':
            (left_shape,left),(right_shape,right)=[load(root,e) for e in row['inputs']]
            assert target==tuple(a*b for a,b in zip(left_shape,right_shape))
            expected=sorted(kronecker(left,left_shape,right,right_shape))
        elif kind=='naive':
            n,m,p=target
            expected=sorted((1<<(i*m+j),1<<(j*p+k),1<<(i*p+k)) for i,j,k in product(range(n),range(m),range(p)))
        else:
            assert kind=='seed'
            # Seeds pass the same full tensor gate as every final output.
            expected=sorted(actual)
        assert expected==sorted(actual),(target,kind)
    assert len(report['outputs'])==report['materialized_targets']
    for row in report['outputs']:
        shape,terms=load(root,row['result'])
        assert list(shape)==row['shape'] and len(terms)==row['rank']<row['baseline']
    with tempfile.TemporaryDirectory(prefix='metaflip-composition-audit-') as name:
        temporary=Path(name);jobs=[]
        for i,((shape,digest),body) in enumerate(cases.items()):
            relative=f'{i}.txt';(temporary/relative).write_bytes(body)
            jobs.append((temporary,tensor.Record('x'.join(map(str,shape)),shape,len(body.splitlines()),relative,digest)))
        with ProcessPoolExecutor(max_workers=workers,mp_context=multiprocessing.get_context('fork')) as pool:
            checks=[]
            for i,result in enumerate(pool.map(tensor._verify_one,jobs),1):
                checks.append(result)
                if i%25==0:print(json.dumps(dict(tensors_checked=i,total=len(jobs))),flush=True)
    return dict(complete=True,field='GF(2)',record_claim=False,
        report_sha256=hashlib.sha256(raw).hexdigest(),source_sha256=pins,
        outputs=len(report['outputs']),recipes=len(report['recipes']),bud_recipes=bud_count,
        tensors=len(checks),terms=sum(r.terms for r in checks),pair_xors=sum(r.pair_xors for r in checks),
        results=[asdict(r) for r in checks])


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--workers',type=int,choices=range(1,5),default=2)
    args=parser.parse_args();assert not args.output.exists()
    result=verify(args.root.resolve(),args.workers)
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('results','source_sha256')}),flush=True)
