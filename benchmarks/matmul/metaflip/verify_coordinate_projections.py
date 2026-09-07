#!/usr/bin/env python3
"""Independently rebuild retained coordinate restrictions and full tensors.

This checks constructive bounds, not the search's minimum or completeness.
The projector scans a bit grid rather than using the search's sparse caches.
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
from verify_representation_portfolio import contained,parse_terms

EDGES=((0,1),(1,2),(0,2))


def project_grid(shape,terms,keep):
    assert len(keep)==len(shape)==3
    for n,coords in zip(shape,keep):
        assert coords and all(type(i)is int and 0<=i<n for i in coords)
        assert coords==sorted(set(coords))
    counts=Counter()
    for term in terms:
        values=[]
        for word,(a,b) in zip(term,EDGES):
            value=0
            for i,old_i in enumerate(keep[a]):
                for j,old_j in enumerate(keep[b]):
                    value|=((word>>(old_i*shape[b]+old_j))&1)<<(i*len(keep[b])+j)
            values.append(value)
        if all(values):counts[tuple(values)]+=1
    return sorted(t for t,n in counts.items() if n%2)


def verify(root,workers=2,reconstruct=None):
    root=root.resolve();raw_report=(root/'report.json').read_bytes();report=json.loads(raw_report)
    assert report['complete'] and report['field']=='GF(2)' and not report['record_claim']
    assert report['parents_done']==report['selected_parents']==len(report['rows'])
    assert report['views']==sum(r['views'] for r in report['rows'])
    pins={};cases={};loaded={}
    def load(path,shape,digest):
        shape=tuple(shape);assert len(shape)==3 and all(type(n)is int and 1<=n<=32 for n in shape)
        path=contained(root,path);key=(str(path),shape,digest)
        if key in loaded:return loaded[key]
        raw=path.read_bytes();assert hashlib.sha256(raw).hexdigest()==digest
        lines=[line for line in raw.splitlines() if line.strip() and not line.lstrip().startswith(b'#')]
        rank=int(lines[0]) if lines[0].isdigit() else len(lines)
        terms=parse_terms(raw,rank)
        assert all(all(type(v)is int and 0<v<1<<(shape[a]*shape[b]) for v,(a,b) in zip(t,EDGES)) for t in terms)
        body=''.join('R '+' '.join(map(str,t))+'\n' for t in terms).encode()
        cases[shape,hashlib.sha256(body).hexdigest()]=body
        pins[str(path.relative_to(root))]=digest;loaded[key]=terms
        return terms
    seen=set();improvements={}
    for row in report['outputs']:
        shape=tuple(row['shape']);key=(shape,row['sha256'])
        assert key not in seen;seen.add(key)
        parent=load(row['parent_path'],row['parent_shape'],row['parent_sha256'])
        actual=load(row['path'],shape,row['sha256'])
        assert tuple(map(len,row['keep']))==shape
        expected=(project_grid(row['parent_shape'],parent,row['keep']) if reconstruct is None
                  else reconstruct(row,parent))
        assert expected==sorted(actual) and len(actual)==row['rank']
        assert row['improves_local']==(row['rank']<row['baseline'])
        if row['improves_local']:
            key=tuple(sorted(shape));improvements[key]=min(improvements.get(key,row['rank']),row['rank'])
    with tempfile.TemporaryDirectory(prefix='metaflip-projection-audit-') as name:
        temp=Path(name);jobs=[]
        for i,((shape,digest),body) in enumerate(cases.items()):
            filename=f'{i}.txt';(temp/filename).write_bytes(body)
            jobs.append((temp,tensor.Record('x'.join(map(str,shape)),shape,len(body.splitlines()),filename,digest)))
        with ProcessPoolExecutor(max_workers=workers,mp_context=multiprocessing.get_context('fork')) as pool:
            checked=[]
            for i,result in enumerate(pool.map(tensor._verify_one,jobs),1):
                checked.append(result)
                if i%50==0:print(json.dumps(dict(tensors_checked=i,total=len(jobs))),flush=True)
    return dict(complete=True,field='GF(2)',record_claim=False,search_exhaustion_checked=False,
        report_sha256=hashlib.sha256(raw_report).hexdigest(),source_sha256=pins,
        outputs=len(report['outputs']),improved_shapes=[dict(shape=s,rank=r) for s,r in sorted(improvements.items())],
        tensors=len(checked),terms=sum(r.terms for r in checked),pair_xors=sum(r.pair_xors for r in checked),
        results=[asdict(r) for r in checked])


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--workers',type=int,choices=range(1,5),default=2)
    a=p.parse_args();assert not a.output.exists()
    result=verify(a.root,a.workers)
    a.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('source_sha256','results')}),flush=True)
