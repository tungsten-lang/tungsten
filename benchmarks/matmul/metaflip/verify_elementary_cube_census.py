#!/usr/bin/env python3
"""Replay census source tensors and every reported 2x2x2 replacement.

This does not certify missing-group detection, optimizer completeness, or
novelty. It independently checks actual ranks after substitution/cancellation.
"""
import argparse
from collections import Counter
import gzip
import hashlib
from itertools import zip_longest
import json
from pathlib import Path
import tempfile

import verify_block_composition_records as tensor
from verify_bud_renewal import expand_group, factor_maps
from verify_representation_portfolio import contained, parse_terms


def delta_zero(terms):
    parity = {}
    for u,v,w in terms:
        for a in tensor._set_positions(u):
            for b in tensor._set_positions(v):
                key = a,b
                parity[key] = parity.get(key,0)^w
                if not parity[key]:
                    del parity[key]
    return not parity


def verify(root, inputs_path, plan_path, leaf_path):
    root, inputs_path, plan_path, leaf_path = map(lambda p: Path(p).resolve(),
                                                (root,inputs_path,plan_path,leaf_path))
    blobs = [p.read_bytes() for p in (root/'report.json',inputs_path,plan_path,leaf_path)]
    report, inputs, plan = map(json.loads,blobs[:3])
    for d in (report,inputs,plan):
        assert d['complete'] is True and d['field'] == 'GF(2)' and d['record_claim'] is False
    for suffix, blob in (('/inputs.json',blobs[1]),('/report.json',blobs[2])):
        assert [v for k,v in report['source_sha256'].items() if k.endswith(suffix)] == [hashlib.sha256(blob).hexdigest()]
    assert len(plan['model_shapes']) == len(plan['baseline_recipes'])
    prices = {tuple(s):r['rank'] for s,r in zip(plan['model_shapes'],plan['baseline_recipes'])}
    assert report['requested_parents'] == len(inputs['parents'])
    assert report['all_parents_attempted'] is (len(report['rows']) == len(inputs['parents']))
    assert report['all_detections_complete'] is (report['all_parents_attempted'] and all(r['complete'] for r in report['rows']))
    corpus_path = contained(root,report['corpus']['path'])
    digest = tensor._sha256(corpus_path)
    assert digest == report['corpus']['sha256']
    leaf = parse_terms(blobs[3],7)
    checks, seen_tensors, candidates = [], set(), []
    with tempfile.TemporaryDirectory(prefix='metaflip-cube-replay-') as directory:
        tmp = Path(directory)
        def check(shape, terms):
            body = ''.join('R '+' '.join(map(str,t))+'\n' for t in terms).encode()
            key = tuple(shape),hashlib.sha256(body).hexdigest()
            if key not in seen_tensors:
                (tmp/'tensor.txt').write_bytes(body)
                checks.append(tensor._verify_one((tmp,tensor.Record('x'.join(map(str,shape)),tuple(shape),
                    len(terms),'tensor.txt',key[1]))))
                seen_tensors.add(key)
        check([2,2,2],leaf)
        with gzip.open(corpus_path,'rt') as stream:
            for index,(line,row) in enumerate(zip_longest(stream,report['rows'])):
                assert line is not None and row is not None
                saved, entry = json.loads(line), inputs['parents'][index]
                assert saved['index'] == row['index'] == index
                for key in ('shape','rank','identity'):
                    assert saved[key] == row[key] == entry[key]
                raw = saved['source_text'].encode()
                assert saved['sha256'] == entry['sha256'] == hashlib.sha256(raw).hexdigest()
                shape, rank = entry['shape'], entry['rank']
                assert len(shape) == 3 and all(type(d) is int and 1 <= d <= 32 for d in shape)
                assert type(rank) is int and rank > 0
                terms = parse_terms(raw,rank)
                identity = 'x'.join(map(str,shape))+'\n'+''.join(' '.join(map(str,t))+'\n' for t in sorted(terms))
                assert hashlib.sha256(identity.encode()).hexdigest() == entry['identity']
                check(shape,terms)
                assert row['local_rank'] == prices[tuple(sorted(shape))]
                assert row['formula_bound_if_cube'] == rank-1
                assert row['improves_local_rank'] is (bool(row['groups']) and rank-1 < row['local_rank'])
                masks = set()
                for number,group in enumerate(row['groups']):
                    assert group['elementary_shape'] == [2,2,2]
                    indices = group['indices']
                    assert len(indices) == len(set(indices)) == 8
                    mask = tuple(sorted(indices))
                    assert mask not in masks
                    masks.add(mask)
                    assert factor_maps(terms,group)[0] == [2,2,2]
                    replacement = list(expand_group(shape,terms,[1,1,1],group,[2,2,2],leaf))
                    assert len(replacement) <= 7
                    assert delta_zero([terms[i] for i in indices]+replacement)
                    counts = Counter(terms)
                    counts.subtract(terms[i] for i in indices)
                    counts.update(replacement)
                    actual = [t for t,n in counts.items() if n%2]
                    assert len(actual) <= rank-1
                    if len(actual) < row['local_rank']:
                        check(shape,actual)
                    candidates.append(dict(index=index,group=number,shape=shape,source_rank=rank,
                        formula_bound=rank-1,actual_rank=len(actual),local_rank=row['local_rank'],
                        improves_local_rank=len(actual)<row['local_rank']))
    assert [p.read_bytes() for p in (root/'report.json',inputs_path,plan_path,leaf_path)] == blobs
    assert tensor._sha256(corpus_path) == digest
    return dict(complete=True,field='GF(2)',record_claim=False,search_absence_certified=False,
        report_sha256=hashlib.sha256(blobs[0]).hexdigest(),inputs_sha256=hashlib.sha256(blobs[1]).hexdigest(),
        price_plan_sha256=hashlib.sha256(blobs[2]).hexdigest(),leaf_sha256=hashlib.sha256(blobs[3]).hexdigest(),
        corpus_sha256=digest,parents=len(report['rows']),groups=len(candidates),
        tensors=len(checks),terms=sum(c.terms for c in checks),pair_xors=sum(c.pair_xors for c in checks),
        improved_shapes=sorted({tuple(c['shape']) for c in candidates if c['improves_local_rank']}),
        candidates=candidates)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('root','inputs','price-plan','leaf','output'):
        parser.add_argument('--'+name,type=Path,required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error('output must not exist')
    result = verify(args.root,args.inputs,args.price_plan,args.leaf)
    with args.output.open('x') as stream:
        stream.write(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k != 'candidates'}))
