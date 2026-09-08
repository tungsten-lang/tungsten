#!/usr/bin/env python3
"""Bounded exact coordinate restrictions of full GF(2) parent tensors.

The searched family is explicitly enumerated. A rank is a constructive upper
bound, not an optimum or novelty claim. Global identities retain full terms.
"""
from __future__ import annotations

import argparse
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
from functools import partial
import hashlib
from itertools import combinations, permutations, product
import json
import math
import multiprocessing
from pathlib import Path
import time

from extend_composition_parents import identity
from verify_representation_portfolio import parse_terms

EDGES=((0,1),(1,2),(0,2))


def validate_keep(shape,keep):
    if len(shape)!=3 or len(keep)!=3 or any(type(n)is not int or n<1 for n in shape):
        raise ValueError('invalid source shape')
    for n,coordinates in zip(shape,keep):
        if not coordinates or any(type(i)is not int or not 0<=i<n for i in coordinates):
            raise ValueError('invalid kept coordinate')
        if tuple(coordinates)!=tuple(sorted(set(coordinates))):
            raise ValueError('kept coordinates must be increasing and distinct')


def restrict_word(value,columns,rows,cols):
    row_map={old:new for new,old in enumerate(rows)}
    col_map={old:new for new,old in enumerate(cols)}
    out=0
    while value:
        bit=value&-value;i,j=divmod(bit.bit_length()-1,columns);value^=bit
        if i in row_map and j in col_map:
            out|=1<<(row_map[i]*len(cols)+col_map[j])
    return out


class ProjectionCache:
    def __init__(self,shape,terms):
        self.shape=tuple(shape);self.terms=tuple(map(tuple,terms));self.cache={}
        if len(self.shape)!=3 or any(type(n)is not int or n<1 for n in self.shape):
            raise ValueError('invalid source shape')
        if any(len(t)!=3 or any(type(v)is not int or v<0 or v>=1<<(self.shape[a]*self.shape[b])
               for v,(a,b) in zip(t,EDGES)) for t in self.terms):
            raise ValueError('invalid factor mask')
        self.width=max(1,len(self.terms).bit_length())

    def column(self,axis,rows,cols):
        key=(axis,tuple(rows),tuple(cols))
        if key not in self.cache:
            _a,b=EDGES[axis]
            transformed={v:restrict_word(v,self.shape[b],rows,cols) for v in {t[axis] for t in self.terms}}
            words=(0,)+tuple(sorted(set(transformed.values())-{0}))
            ids={value:i for i,value in enumerate(words)}
            self.cache[key]=(tuple(ids[transformed[t[axis]]] for t in self.terms),words)
        return self.cache[key]

    def restrict(self,keep,materialize=False):
        validate_keep(self.shape,keep)
        columns=[self.column(axis,keep[a],keep[b]) for axis,(a,b) in enumerate(EDGES)]
        u,v,w=(c[0] for c in columns);width=self.width;twice=2*width
        parity=set()
        for a,b,c in zip(u,v,w):
            if a and b and c:
                code=a|(b<<width)|(c<<twice)
                if code in parity:parity.remove(code)
                else:parity.add(code)
        if not materialize:return len(parity)
        mask=(1<<width)-1
        return sorted((columns[0][1][k&mask],columns[1][1][(k>>width)&mask],
                       columns[2][1][k>>twice]) for k in parity)


def families(shape,targets,max_views,max_deleted_axes=3):
    """Delete zero/one coordinate on each axis, plus named subset families."""
    if type(max_deleted_axes) is not int or not 1<=max_deleted_axes<=3:
        raise ValueError('max_deleted_axes must be 1, 2, or 3')
    full=tuple(tuple(range(n)) for n in shape)
    axes=[(all_,)+tuple(tuple(i for i in all_ if i!=drop) for drop in all_) if len(all_)>1 else (all_,)
          for all_ in full]
    if max_deleted_axes==3:
        # Keep the established default domain, order and family accounting.
        yield 'one-per-axis',axes,math.prod(map(len,axes))-1
    else:
        active=[axis for axis,n in enumerate(shape) if n>1]
        for count in range(1,max_deleted_axes+1):
            for deleted in combinations(active,count):
                choices=[axis[1:] if i in deleted else axis[:1] for i,axis in enumerate(axes)]
                yield 'delete-axes-'+'-'.join(map(str,deleted)),choices,math.prod(map(len,choices))
    for target in sorted({p for t in targets for p in permutations(t)}):
        if any(t>n for t,n in zip(target,shape)) or tuple(target)==tuple(shape):continue
        count=math.prod(math.comb(n,t) for n,t in zip(shape,target))
        if count>max_views:
            yield 'target-'+'x'.join(map(str,target)),None,count
        else:
            yield 'target-'+'x'.join(map(str,target)),[tuple(combinations(range(n),t)) for n,t in zip(shape,target)],count


def scan_parent(job,max_deleted_axes=3):
    entry,targets,max_views=job
    raw=Path(entry['path']).read_bytes()
    assert hashlib.sha256(raw).hexdigest()==entry['sha256'],'source hash changed'
    terms=parse_terms(raw,entry['rank']);shape=tuple(entry['shape'])
    assert identity(shape,terms)==entry['identity'],'source identity changed'
    cache=ProjectionCache(shape,terms);full=tuple(tuple(range(n)) for n in shape)
    seen=set();best={};skipped=[];family_counts={};start=time.process_time()
    for name,axes,count in families(shape,targets,max_views,max_deleted_axes):
        if axes is None:
            skipped.append(dict(family=name,views=count,reason='explicit per-family view allowance'));continue
        checked=0
        for keep in product(*axes):
            if keep==full or keep in seen:continue
            seen.add(keep);checked+=1
            target=tuple(map(len,keep));rank=cache.restrict(keep)
            prior=best.get(target)
            if prior is None or (rank,keep)<(prior['rank'],prior['keep']):
                best[target]=dict(shape=target,rank=rank,keep=keep)
        family_counts[name]=checked
    rows=[]
    for target,row in sorted(best.items()):
        result=cache.restrict(row['keep'],materialize=True)
        assert len(result)==row['rank']
        rows.append(dict(row,terms=result))
    return dict(parent=entry['id'],source=entry,views=len(seen),families=family_counts,
                skipped=skipped,rows=rows,cpu_seconds=time.process_time()-start)


def text(terms):return (str(len(terms))+'\n'+''.join(' '.join(map(str,t))+'\n' for t in terms)).encode()


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--inputs',type=Path,required=True)
    p.add_argument('--prices',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--max-source-rank',type=int,default=512)
    p.add_argument('--max-source-dimension',type=int,default=12)
    p.add_argument('--max-family-views',type=int,default=20000)
    p.add_argument('--max-deleted-axes',type=int,choices=(1,2,3),default=3,
        help='base neighborhood: delete at most one coordinate on this many axes; named --target families are unchanged')
    p.add_argument('--target',action='append',default=[])
    p.add_argument('--workers',type=int,choices=range(1,5),default=2)
    a=p.parse_args();assert not a.output.exists()
    assert a.max_source_rank>0 and a.max_source_dimension>0 and a.max_family_views>0
    targets=[tuple(map(int,t.split('x'))) for t in a.target]
    assert all(len(t)==3 and all(n>0 for n in t) for t in targets)
    inputs=json.loads(a.inputs.read_bytes());plan=json.loads(a.prices.read_bytes())
    assert inputs['complete'] and plan['complete'] and not plan['record_claim'] and plan['field']=='GF(2)'
    prices={tuple(s):r['rank'] for s,r in zip(plan['model_shapes'],plan['baseline_recipes'])}
    selected=[dict(p,id=i) for i,p in enumerate(inputs['parents'])
              if p['rank']<=a.max_source_rank and max(p['shape'])<=a.max_source_dimension and min(p['shape'])>=2]
    a.output.mkdir();(a.output/'parents').mkdir();(a.output/'tensors').mkdir()
    pins={str(path.resolve()):hashlib.sha256(path.read_bytes()).hexdigest()
          for path in [a.inputs,a.prices,Path(__file__),Path(__file__).with_name('extend_composition_parents.py'),
                       Path(__file__).with_name('verify_representation_portfolio.py')]}
    report=dict(complete=False,field='GF(2)',record_claim=False,canonical_archive_changed=False,
        source_sha256=pins,limits=dict(max_source_rank=a.max_source_rank,
        max_source_dimension=a.max_source_dimension,max_family_views=a.max_family_views,
        max_deleted_axes=a.max_deleted_axes,targets=targets),
        selected_parents=len(selected),parents_done=0,views=0,rows=[],outputs=[],source_cpu_seconds=0)
    best={};start=time.monotonic()
    def save():
        report['elapsed_seconds']=time.monotonic()-start
        pending=a.output/'report.pending.json';pending.write_text(json.dumps(report,indent=2)+'\n')
        pending.replace(a.output/'report.json')
    save()
    with ProcessPoolExecutor(max_workers=a.workers,mp_context=multiprocessing.get_context('fork')) as pool:
        jobs=((entry,targets,a.max_family_views) for entry in selected)
        for result in pool.map(partial(scan_parent,max_deleted_axes=a.max_deleted_axes),jobs):
            entry=result.pop('source');raw=Path(entry['path']).read_bytes()
            assert hashlib.sha256(raw).hexdigest()==entry['sha256']
            parent_name=f"parents/{entry['id']}.txt";(a.output/parent_name).write_bytes(raw)
            pins[str(Path(entry['path']).resolve())]=entry['sha256']
            report['views']+=result['views'];report['source_cpu_seconds']+=result['cpu_seconds']
            for row in result['rows']:
                target=tuple(row['shape']);key=tuple(sorted(target));terms=row.pop('terms')
                row['baseline']=prices[key]
                old=best.get(target)
                if old is None or (row['rank'],entry['id'],row['keep'])<(old['rank'],old['parent'],old['keep']):
                    best[target]=dict(row,parent=entry['id'],parent_shape=entry['shape'],
                        parent_path=parent_name,parent_sha256=entry['sha256'],terms=terms)
            report['rows'].append(result);report['parents_done']+=1
            if report['parents_done']%25==0:
                save();print(json.dumps(dict(done=report['parents_done'],total=len(selected),views=report['views'],
                    elapsed=report['elapsed_seconds'],improved_orientations=sum(r['rank']<r['baseline'] for r in best.values()))),flush=True)
    for target,row in sorted(best.items()):
        terms=row.pop('terms');data=text(terms);digest=hashlib.sha256(data).hexdigest()
        name='tensors/'+'x'.join(map(str,target))+'-'+digest+'.txt';(a.output/name).write_bytes(data)
        row.update(path=name,sha256=digest,improves_local=row['rank']<row['baseline'])
        report['outputs'].append(row)
    assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in pins.items())
    report['complete']=True;save()
    print(json.dumps(dict(complete=True,parents=report['parents_done'],views=report['views'],
        output_orientations=len(report['outputs']),improvements=[{k:v for k,v in r.items()
        if k in ('shape','rank','baseline','parent','keep')} for r in report['outputs'] if r['improves_local']],
        elapsed_seconds=report['elapsed_seconds'],source_cpu_seconds=report['source_cpu_seconds'])),flush=True)


if __name__=='__main__':main()
