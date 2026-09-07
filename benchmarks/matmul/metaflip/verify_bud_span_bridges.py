#!/usr/bin/env python3
"""Replay targeted flip words and independently reconstruct every tensor.

This is an exact witness checker, not a completeness or record certificate.
It does not import the Ruby search implementation.
"""
import argparse
from collections import Counter
from concurrent.futures import ProcessPoolExecutor
from dataclasses import asdict
import hashlib
import json
import multiprocessing
from pathlib import Path
import tempfile

import verify_block_composition_records as tensor
from verify_representation_portfolio import contained, parse_terms


def binary_rank(words):
    pivots={}
    for word in words:
        while word:
            p=word.bit_length()-1
            if p not in pivots:
                pivots[p]=word
                break
            word^=pivots[p]
    return len(pivots)


def xor_mask(words, mask):
    assert type(mask) is int and 0<mask<1<<len(words)
    value=0
    for i,w in enumerate(words):
        if mask>>i&1:value^=w
    return value


def flip(terms, step):
    assert len(step)==4 and all(type(i) is int for i in step)
    shared,added,i,j=step
    assert 0<=shared<3 and 0<=added<3 and shared!=added
    assert 0<=i<len(terms) and 0<=j<len(terms) and i!=j
    assert terms[i][shared]==terms[j][shared]
    other=({0,1,2}-{shared,added}).pop()
    a,b=terms[i].copy(),terms[j].copy()
    terms[j][added]=a[added]^b[added]
    terms[i][other]=a[other]^b[other]


def replay(source, row):
    a,c=row['shared_axis'],row['aligned_axis']
    assert type(a) is int and type(c) is int and 0<=a<3 and 0<=c<3 and a!=c
    groups=row['groups']
    assert len(groups)==2 and all(g and len(g)==len(set(g)) for g in groups)
    assert not set(groups[0])&set(groups[1])
    values=[]
    for group in groups:
        assert all(type(i) is int and 0<=i<len(source) for i in group)
        fixed=source[group[0]][a]
        assert group==[i for i,t in enumerate(source) if t[a]==fixed]
        values.append([source[i][c] for i in group])
    assert len(row['masks'])==2
    assert all(xor_mask(v,m)==row['target'] for v,m in zip(values,row['masks']))
    assert row['intersection_dimension']==binary_rank(values[0])+binary_rank(values[1])-binary_rank(values[0]+values[1])
    word=row['word']
    assert 2<=len(word)<=len(groups[0])+len(groups[1])-1
    terms=[list(t) for t in source]
    for step in word[:-1]:
        assert step[:2]==[a,c]
        assert any(step[2] in g and step[3] in g for g in groups)
        flip(terms,step)
    last=word[-1]
    assert last[:2]==[c,a]
    assert (last[2] in groups[0] and last[3] in groups[1]) or (last[2] in groups[1] and last[3] in groups[0])
    assert terms[last[2]][c]==terms[last[3]][c]==row['target']>0
    flip(terms,last)
    reverse=[t.copy() for t in terms]
    for step in reversed(word):flip(reverse,step)
    assert reverse==[list(t) for t in source]
    parity=Counter(tuple(t) for t in terms if all(t))
    return sorted(t for t,n in parity.items() if n%2)


def verify(root, workers=2):
    root=root.resolve();raw=(root/'report.json').read_bytes();r=json.loads(raw)
    assert r['complete'] and r['field']=='GF(2)' and not r['record_claim']
    assert r['family']=='bounded-cross-bud-span-bridges'
    bounds=r['bounds']
    assert 1<=bounds['max_group']<=32 and 1<=bounds['max_vectors']<=255 and 1<=bounds['max_pivots']<=32
    tensors={};pins={}
    def load(e):
        shape=tuple(e['shape']);assert len(shape)==3 and all(type(d) is int and 1<=d<=32 for d in shape)
        path=contained(root,e['path']);body=path.read_bytes()
        assert hashlib.sha256(body).hexdigest()==e['sha256']
        pins[e['path']]=e['sha256']
        terms=parse_terms(body,int(body.splitlines()[0]))
        widths=(shape[0]*shape[1],shape[1]*shape[2],shape[0]*shape[2])
        assert all(all(0<v<1<<w for v,w in zip(t,widths)) for t in terms)
        converted=''.join('R '+' '.join(map(str,t))+'\n' for t in terms).encode()
        tensors[shape,hashlib.sha256(converted).hexdigest()]=converted
        return terms
    parents=[load(e) for e in r['parents']]
    counts=Counter();minima=[len(p) for p in parents];steps=Counter();seen=set()
    for row in r['candidates']:
        i=row['parent'];assert type(i) is int and 0<=i<len(parents)
        assert all(len(g)<=bounds['max_group'] for g in row['groups'])
        actual=replay(parents[i],row);final=load(row['result'])
        assert row['result']['shape']==r['parents'][i]['shape'] and actual==sorted(final)
        assert len(final)<=len(parents[i]) and len(final)==len(set(final))
        key=(i,tuple(actual));assert key not in seen;seen.add(key)
        counts[i]+=1;steps[i]+=len(row['word']);minima[i]=min(minima[i],len(final))
    assert len(r['summaries'])==len(parents)
    for i,s in enumerate(r['summaries']):
        assert s['rank']==len(parents[i]) and s['min_rank']==minima[i]
        assert s['candidates']==counts[i]<=bounds['max_proposals_per_input']
        assert s['elementary_flips']==steps[i]
    with tempfile.TemporaryDirectory(prefix='metaflip-span-bridge-audit-') as directory:
        tmp=Path(directory);jobs=[]
        for i,((shape,digest),body) in enumerate(tensors.items()):
            name=f'{i}.txt';(tmp/name).write_bytes(body)
            jobs.append((tmp,tensor.Record('x'.join(map(str,shape)),shape,len(body.splitlines()),name,digest)))
        with ProcessPoolExecutor(max_workers=workers,mp_context=multiprocessing.get_context('fork')) as pool:
            checks=list(pool.map(tensor._verify_one,jobs))
    return dict(complete=True,field='GF(2)',record_claim=False,report_sha256=hashlib.sha256(raw).hexdigest(),
        parents=len(parents),candidates=sum(counts.values()),elementary_flips=sum(steps.values()),
        unique_tensors=len(checks),terms=sum(c.terms for c in checks),pair_xors=sum(c.pair_xors for c in checks),
        source_sha256=pins,results=[asdict(c) for c in checks])


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root',type=Path,required=True)
    p.add_argument('--workers',type=int,choices=range(1,5),default=2)
    p.add_argument('--report',type=Path,required=True)
    args=p.parse_args();assert not args.report.exists()
    result=verify(args.root,args.workers)
    args.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('source_sha256','results')}))
