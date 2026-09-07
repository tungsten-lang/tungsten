#!/usr/bin/env python3
"""Reprice verified full parent states at all bounded scales (pure buckets).

Exact tensor identities remain distinct. Only the read-only price calculation
is cached by equal-factor bucket sizes; this is not search-state dominance.
Positive rows still require materialization before larger-tensor admission.
"""
import argparse
from collections import Counter
from functools import lru_cache
import hashlib
from itertools import product
import json
import math
from pathlib import Path

from verify_representation_portfolio import contained, parse_terms


def bucket_signature(terms):
    return tuple(tuple(sorted(Counter(t[a] for t in terms).values())) for a in range(3))


def rescore(root, price_path, output, maximum=32):
    root=root.resolve()
    assert not output.exists()
    pins={}
    def read(path):
        raw=path.read_bytes();pins[str(path.resolve())]=hashlib.sha256(raw).hexdigest()
        return json.loads(raw)
    summary=read(root/'report.json');audit=read(root/'independent-audit.json')
    assert summary['complete'] and audit['complete'] and not summary['record_claim'] and not audit['record_claim']
    assert summary['total_attempts']==audit['attempts']
    report=read(price_path)
    assert report['complete'] and report['field']=='GF(2)' and not report['record_claim']
    prices={tuple(r['shape']):r.get('rank',r.get('augmented_rank')) for r in report['rows']}
    assert all(type(v) is int and v>0 for v in prices.values())
    assert 2<=maximum<=32
    def price(shape):
        return math.prod(shape) if 1 in shape else prices[tuple(sorted(shape))]
    parents={}
    for row in summary['rows']:
        path=contained(root,row['report']);study=read(path)
        shape=tuple(study['parent']['shape'])
        entries=[(path.parent/study['parent']['path'],study['parent']['sha256'],'initial')]
        for arm in study['arms']:
            for trial in arm['trials']:
                i=trial['trial']
                for kind,prefix,metric in (('winner','trial','parent'),('end','end','end_parent')):
                    entries.append((path.parent/arm['mode']/f'{prefix}-{i}.txt',trial[metric]['sha256'],kind))
        for candidate,digest,kind in entries:
            relative=str(candidate.relative_to(root));raw=candidate.read_bytes()
            assert hashlib.sha256(raw).hexdigest()==digest==audit['source_sha256'][relative]
            pins[str(candidate)]=digest
            terms=parse_terms(raw,int(raw.splitlines()[0]))
            key=shape,tuple(sorted(terms))
            entry=parents.setdefault(key,dict(shape=shape,rank=len(terms),path=relative,sha256=digest,
                                             signature=bucket_signature(terms),origins=[]))
            entry['origins'].append(dict(path=relative,kind=kind))
    @lru_cache(None)
    def bucket(axis,scale,k):
        expanded=(2,0,1)[axis]
        chunks=[]
        for j in range(1,min(k,maximum//scale[expanded])+1):
            leaf=list(scale);leaf[expanded]*=j
            chunks.append(price(leaf))
        dp=[0]
        for n in range(1,k+1):
            dp.append(min(dp[n-j]+chunks[j-1] for j in range(1,min(n,len(chunks))+1)))
        return dp[k]
    @lru_cache(None)
    def score(signature,scale):
        costs=tuple(sum(bucket(a,scale,k) for k in signature[a]) for a in range(3))
        return min(costs),costs.index(min(costs))
    rows=[];checks=0;by_target={};signatures=set()
    for identity,parent in enumerate(parents.values()):
        shape=parent['shape'];signature=parent['signature'];signatures.add((shape,signature))
        for scale in product(*(range(1,maximum//d+1) for d in shape)):
            if scale==(1,1,1):continue
            target=tuple(sorted(d*s for d,s in zip(shape,scale)))
            formula,axis=score(signature,scale);checks+=1
            old=by_target.get(target)
            if old is None or formula<old['formula']:
                by_target[target]=dict(target=target,parent=identity,scale=scale,axis=axis,
                                       formula=formula,baseline=price(target),gain=price(target)-formula)
    rows=sorted(by_target.values(),key=lambda r:r['target'])
    result=dict(complete=True,screen_only=True,field='GF(2)',record_claim=False,maximum=maximum,
        family='all bounded scales with exact pure-axis bucket DP; no larger tensor admission',
        parent_states=len(parents),price_signatures=len(signatures),parent_scale_checks=checks,
        targets=len(rows),improved_targets=sum(r['gain']>0 for r in rows),
        score_cache=score.cache_info()._asdict(),bucket_cache=bucket.cache_info()._asdict(),
        source_sha256=pins,parents=list(parents.values()),rows=rows)
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(result,indent=2)+'\n')
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root',type=Path,required=True)
    p.add_argument('--prices',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    result=rescore(a.root,a.prices,a.output)
    print(json.dumps({k:v for k,v in result.items() if k not in ('source_sha256','parents','rows')}))
    for row in result['rows']:
        if row['gain']>0:print(json.dumps(row))
