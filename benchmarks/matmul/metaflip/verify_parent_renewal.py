#!/usr/bin/env python3
"""Replay a bounded parent-variant study, never certify global novelty."""
import argparse
from collections import defaultdict
import hashlib
from itertools import permutations, product
import json
from pathlib import Path
import tempfile

import catalog_gf2_import as importer
from verify_bud_renewal import EDGES, elementary, factor_maps, verify_products
from verify_representation_portfolio import contained, identity, parse_terms
from verify_recursive_portfolio import verify as verify_closure


def orient(shape, terms):
    target = sorted(shape)
    order = next(p for p in permutations(range(3)) if [shape[i] for i in p] == target)
    result = []
    for term in terms:
        out = []
        for a, b in EDGES:
            r, c = order[a], order[b]
            index = EDGES.index(tuple(sorted((r,c))))
            word = term[index]
            if r > c:
                value = 0
                while word:
                    bit = word & -word
                    i, j = divmod(bit.bit_length()-1, shape[r])
                    value ^= 1 << (j*shape[c]+i)
                    word ^= bit
                word = value
            out.append(word)
        result.append(tuple(out))
    return target, result


def check_screen(root, screen, baseline):
    assert screen['complete'] and screen['field'] == 'GF(2)' and not screen['record_claim']
    assert (screen['max_dimension'],screen['max_leaf'],screen['trials'],screen['seed']) == (32,32,8,202609079)
    prices = {tuple(r['shape']):r['augmented_rank'] for r in baseline['rows']}
    def rank(shape):
        assert all(1 <= d <= 32 for d in shape)
        return shape[0]*shape[1]*shape[2] if 1 in shape else prices[tuple(sorted(shape))]
    def load(entry):
        raw = contained(root,entry['path']).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == entry['sha256']
        return parse_terms(raw,int(raw.splitlines()[0]))
    parents = [(p['snapshot']['shape'],load(p['snapshot'])) for p in screen['parents']]
    ids = [identity(s,t) for s,t in parents]
    assert ids == [p['id'] for p in screen['parents']] and len(set(ids)) == len(ids)
    for (s,t),p in zip(parents,screen['parents']):
        assert s == sorted(s) and len(t) == p['rank']
    with tempfile.TemporaryDirectory(prefix='parent-source-replay-') as directory:
        for source in screen['sources']:
            path = contained(root,'sources/'+source['blob']+'.json')
            raw = path.read_bytes()
            assert hashlib.sha256(raw).hexdigest() == source['source_sha256']
            assert hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest() == source['blob']
            output = Path(directory)/'converted.txt'
            shape,count = importer.convert(path,output)
            assert list(shape) == source['shape'] and count == source['rank']
            target,terms = orient(shape,parse_terms(output.read_bytes(),count))
            assert identity(target,terms) == source['parent_id']
            assert identity(source['snapshot']['shape'],load(source['snapshot'])) == source['parent_id']
    per_shape = defaultdict(list)
    for i,(shape,terms) in enumerate(parents):
        per_shape[tuple(shape)].append(i)
    leaders = {min(indices,key=lambda i:(len(parents[i][1]),sum(v.bit_count() for t in parents[i][1] for v in t),ids[i]))
               for indices in per_shape.values()}
    minima = {s:min(len(parents[i][1]) for i in indices) for s,indices in per_shape.items()}
    expected = {(i,scale) for i,(shape,_) in enumerate(parents)
                for scale in product(*(range(1,32//d+1) for d in shape)) if scale != (1,1,1)}
    seen, by_target = set(),defaultdict(list)
    for row in screen['rows']:
        i,scale = row['parent'],tuple(row['scale'])
        key = i,scale
        assert key in expected and key not in seen
        seen.add(key)
        shape,terms = parents[i]
        assert (row['parent_id'],row['parent_shape'],row['parent_rank']) == (ids[i],shape,len(terms))
        assert row['leader'] == (i in leaders) and row['minimum_rank'] == (len(terms)==minima[tuple(shape)])
        assert sorted(j for g in row['groups'] for j in g['indices']) == list(range(len(terms)))
        formula = 0
        for group in row['groups']:
            block,_ = factor_maps(terms,group)
            formula += rank([d*s for d,s in zip(block,scale)])
        target = sorted(d*s for d,s in zip(shape,scale))
        assert target == row['target'] and formula == row['formula']
        assert (row['baseline'],row['gain']) == (rank(target),rank(target)-formula)
        by_target[tuple(target)].append(row)
    assert seen == expected
    selected = [min(rr,key=lambda r:(r['formula'],r['parent'],r['scale'])) for rr in by_target.values()]
    selected = sorted((r for r in selected if r['gain']>0),key=lambda r:(-r['gain'],r['target']))
    assert selected == screen['selected']
    controls = {tuple(r['shape']):r for r in screen['controls']}
    assert set(controls) == set(by_target)
    for shape,rows in by_target.items():
        assert controls[shape] == dict(shape=list(shape),all=min(r['formula'] for r in rows),
            leader=min(r['formula'] for r in rows if r['leader']),
            minimum_rank=min(r['formula'] for r in rows if r['minimum_rank']))
    return dict(sources=len(screen['sources']),parents=len(parents),parent_scales=len(seen),
                targets=len(by_target),lower_formula_targets=len(selected),
                all_beats_leader=sum(r['all']<r['leader'] for r in controls.values()),
                all_beats_minimum_rank=sum(r['all']<r['minimum_rank'] for r in controls.values()),
                partition_optimality_claim=False,matched_runtime_claim=False)


def verify(root, workers=2):
    root = root.resolve()
    read = lambda path:json.loads(path.read_text())
    report = read(root/'report.json')
    assert report['kind'] == 'parent-renewal' and report['complete']
    assert report['field'] == 'GF(2)' and report['record_claim'] is False and report['redistribution_cleared'] is False
    for name,digest in report['retained_files'].items():
        assert hashlib.sha256(contained(root,name).read_bytes()).hexdigest() == digest, name
    baseline_root = root/'reconciliation/closure'
    baseline = read(baseline_root/'report.json')
    baseline_check = verify_closure(baseline_root,baseline_root/'admitted',
        Path(__file__).with_name('verify_block_composition_records.py'),workers)
    assert baseline_check['improved_shapes'] == 0
    screen = read(root/'parents/screen.json')
    screen_check = check_screen(root/'parents',screen,baseline)
    selected = {tuple(r['target']):r for r in screen['selected']}
    for row in report['outputs']:
        expected = selected[tuple(row['target'])]
        assert all(row[k] == expected[k] for k in ('formula','baseline','gain','parent_id','parent','scale'))
        path = contained(root,row['recipe'])
        recipe = read(path)
        assert [{k:v for k,v in g.items() if k != 'leaf'} for g in recipe['groups']] == expected['groups']
    assert len(report['outputs']) == report['materialized_targets']
    products = verify_products(root,report['outputs'],baseline,workers)
    return dict(schema=1,complete=True,field='GF(2)',record_claim=False,screen=screen_check,
                baseline={k:v for k,v in baseline_check.items() if k!='cases'},
                products=products)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--workers',type=int,choices=range(1,5),default=2)
    parser.add_argument('--report',type=Path)
    args = parser.parse_args()
    result = verify(args.root,args.workers)
    if args.report:
        args.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({**result,'products':{k:v for k,v in result['products'].items() if k!='results'}}))
