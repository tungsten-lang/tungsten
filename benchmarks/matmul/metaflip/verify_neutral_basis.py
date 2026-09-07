#!/usr/bin/env python3
"""Replay bounded neutral column-basis paths and all complete GF(2) tensors."""
import argparse
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
from dataclasses import asdict
import hashlib
from itertools import permutations, product
import json
import multiprocessing
from pathlib import Path
import tempfile

from verify_cofactor_mergers import compress_shared, refactor_shared
from verify_representation_portfolio import contained, parse_terms
import verify_block_composition_records as tensor


def encode(terms):
    return (str(len(terms))+'\n'+''.join(' '.join(map(str,t))+'\n' for t in sorted(terms))).encode()


def digest(body):
    return hashlib.sha256(body).hexdigest()


def replay_case(job):
    root, rows = job
    entry=rows[0]['input'];raw=contained(root,entry['path']).read_bytes()
    assert digest(raw)==entry['sha256']
    shape=entry['shape'];initial=parse_terms(raw,rows[0]['rank_before'])
    assert len(shape)==3 and all(type(n)is int and 1<=n<=32 for n in shape)
    width=max(shape[0]*shape[1],shape[1]*shape[2],shape[0]*shape[2])
    cache={};entries=[entry];configs=set();step_count=0
    for row in rows:
        assert row['input']==entry and row['rank_before']==len(initial) and row['max_bits']==width
        order, reverse=tuple(row['order']),row['reverse_columns']
        assert sorted(order)==[0,1,2] and type(reverse)is bool
        assert (order,reverse) not in configs;configs.add((order,reverse))
        terms=list(initial);seen={digest(encode(terms))};steps=[]
        for _ in range(2):
            for axis in order:
                before=digest(encode(terms));key=(tuple(terms),axis,reverse)
                if key not in cache:
                    cache[key]=refactor_shared(terms,axis,max_bits=width,reverse_columns=reverse)
                terms,changed=cache[key]
                steps.append(dict(axis=axis,before_sha256=before,after_sha256=digest(encode(terms)),
                                  changed_groups=len(changed),rank=len(terms)))
            h=digest(encode(terms))
            if h in seen:break
            seen.add(h)
        assert row['steps']==steps
        terms,history=compress_shared(terms,max_bits=width)
        assert row['compression']==history and row['rank_after']==len(terms)<=len(initial)
        result=row['result'];body=contained(root,result['path']).read_bytes()
        assert result['shape']==shape and digest(body)==result['sha256']
        assert body==encode(terms)
        entries.append(result);step_count+=len(steps)
    return dict(entries=entries,steps=step_count,distinct_transitions=len(cache),configs=len(configs))


def verify(root,workers=2):
    root=Path(root).resolve();raw=(root/'report.json').read_bytes();report=json.loads(raw)
    assert report['complete'] and report['field']=='GF(2)' and not report['record_claim']
    assert not report['canonical_archive_changed'] and report['passes']==2
    assert report['completed_trials']==len(report['rows'])<=report['planned_trials']
    assert report['all_planned_trials_completed']==(len(report['rows'])==report['planned_trials'])
    assert report['rank_drop_trials']==sum(r['rank_after']<r['rank_before'] for r in report['rows'])
    assert report['distinct_endpoints']==len({r['result']['sha256'] for r in report['rows']})
    groups=defaultdict(list)
    for row in report['rows']:groups[row['input']['sha256']].append(row)
    if report['all_planned_trials_completed']:
        assert report['planned_trials']==12*len(groups)
        for rows in groups.values():
            assert {(tuple(r['order']),r['reverse_columns']) for r in rows}==set(product(permutations(range(3)),(False,True)))
    pins={};entries={};steps=0;transitions=0
    with ProcessPoolExecutor(max_workers=workers,mp_context=multiprocessing.get_context('fork')) as pool:
        for i,result in enumerate(pool.map(replay_case,((root,rows) for rows in groups.values())),1):
            steps+=result['steps'];transitions+=result['distinct_transitions']
            for e in result['entries']:
                entries[tuple(e['shape']),e['sha256']]=e;pins[e['path']]=e['sha256']
            print(json.dumps(dict(cases_replayed=i,total=len(groups))),flush=True)
    with tempfile.TemporaryDirectory(prefix='metaflip-neutral-basis-full-') as directory:
        tmp=Path(directory);jobs=[]
        for i,e in enumerate(entries.values()):
            body=contained(root,e['path']).read_bytes();terms=parse_terms(body,int(body.splitlines()[0]))
            data=''.join('R '+' '.join(map(str,t))+'\n' for t in terms).encode()
            name=str(i)+'.txt';(tmp/name).write_bytes(data)
            jobs.append((tmp,tensor.Record('x'.join(map(str,e['shape'])),tuple(e['shape']),len(terms),name,digest(data))))
        with ProcessPoolExecutor(max_workers=workers,mp_context=multiprocessing.get_context('fork')) as pool:
            full=[]
            for value in pool.map(tensor._verify_one,jobs):
                full.append(value)
                if len(full)%8==0:print(json.dumps(dict(tensors_verified=len(full),total=len(jobs))),flush=True)
    return dict(complete=True,field='GF(2)',record_claim=False,report_sha256=digest(raw),
                trials=len(report['rows']),steps=steps,distinct_transitions=transitions,
                rank_drop_trials=report['rank_drop_trials'],tensors=len(full),
                terms=sum(r.terms for r in full),pair_xors=sum(r.pair_xors for r in full),
                source_sha256=pins,results=[asdict(r) for r in full])


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root',type=Path)
    parser.add_argument('--workers',type=int,choices=range(1,5),default=2)
    args=parser.parse_args();result=verify(args.root,args.workers)
    output=args.root/'independent-audit.json';assert not output.exists()
    output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('source_sha256','results')}))
