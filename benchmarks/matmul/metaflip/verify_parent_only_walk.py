#!/usr/bin/env python3
"""Independent tensor and price replay for parent-only composition walks.

This verifies saved full tensors, leaf-backed scores, and attempt accounting.
It does not prove that a search was exhaustive or export any larger tensor.
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
from verify_bud_renewal import factor_maps


def pure_score(terms, prices):
    assert len(prices) == 3 and all(row[0] == 0 for row in prices)
    return min(sum(prices[axis][count] for count in Counter(t[axis] for t in terms).values())
               for axis in range(3))


def cover_score(terms, prices, held=(), held_cost=None):
    best = pure_score(terms, prices)
    if held_cost is not None and all(t in terms for t in held):
        keep = set(held)
        best = min(best, held_cost + pure_score([t for t in terms if t not in keep], prices))
    return best


def verify(root, workers=2):
    root = root.resolve()
    read = lambda path: json.loads(path.read_text())
    summary = read(root/'report.json')
    assert summary['complete'] and summary['field'] == 'GF(2)' and not summary['record_claim']
    tensors, pins = {}, {}

    def load(path, shape, digest):
        shape = tuple(shape)
        assert len(shape) == 3 and all(type(d) is int and 1 <= d <= 32 for d in shape)
        raw = path.read_bytes()
        assert hashlib.sha256(raw).hexdigest() == digest, path
        pins[str(path.relative_to(root))] = digest
        terms = parse_terms(raw, int(raw.splitlines()[0]))
        assert len(set(terms)) == len(terms)
        body = ''.join('R '+' '.join(map(str, t))+'\n' for t in terms).encode()
        tensors[shape, hashlib.sha256(body).hexdigest()] = body
        return terms

    def snapshot(base, entry):
        return load(contained(base, entry['path']), entry['shape'], entry['sha256'])

    attempts, winners, ends = 0, 0, 0
    for row in summary['rows']:
        path = contained(root, row['report'])
        study = read(path)
        options = study['options']
        assert options['parents_only'] and not options.get('grids')
        assert study['field'] == 'GF(2)' and not study['record_claim']
        assert study['binary_sha256'] == summary['binary_sha256']
        source = snapshot(path.parent, study['parent'])
        shape = study['parent']['shape']
        cases = study.get('portfolio',[dict(scale=list(map(int,options.get('scale','1x1x1').split('x'))),weight=1)])
        assert 1 <= len(cases) <= 32
        for case in cases:
            assert set(case)=={'scale','weight'}
            assert len(case['scale'])==3 and all(type(d) is int and 1<=d<=16 for d in case['scale'])
            assert type(case['weight']) is int and 1<=case['weight']<=1024
        assert len({tuple(case['scale']) for case in cases})==len(cases)
        if 'portfolio' in study:
            assert study['score_kind']=='weighted-common-axis-portfolio-cost-not-a-tensor-rank'
            raw=contained(path.parent,study['portfolio_source_path']).read_bytes()
            assert hashlib.sha256(raw).hexdigest()==study['portfolio_source_sha256']
            assert json.loads(raw)==cases
        leaves = read(path.parent/'price-leaves.json')
        chunks = [[dict(),dict(),dict()] for _ in cases]
        for leaf in leaves:
            case_index,axis,count = leaf.get('case',0),leaf['axis'],leaf['count']
            assert type(case_index) is int and 0<=case_index<len(cases)
            assert 0 <= axis < 3 and 1 <= count
            expected_shape = cases[case_index]['scale'].copy()
            expected_shape[(2,0,1)[axis]] *= count
            assert leaf['snapshot']['shape'] == expected_shape
            terms = snapshot(path.parent, leaf['snapshot'])
            assert len(terms) == leaf['rank']
            assert count not in chunks[case_index][axis]
            chunks[case_index][axis][count] = len(terms)
        raw = (path.parent/'prices.txt').read_bytes()
        assert hashlib.sha256(raw).hexdigest() == study['price_sha256']
        lines = raw.decode().splitlines()
        assert len(lines) == 4
        limit = int(lines[0])
        assert limit == len(source)+options['debt']
        prices = [list(map(int, line.split())) for line in lines[1:]]
        for axis in range(3):
            assert len(prices[axis]) == limit+1
            combined = [0]*(limit+1)
            for i,case in enumerate(cases):
                assert 1 in chunks[i][axis]
                expected=[0]
                for k in range(1,limit+1):
                    expected.append(min(expected[k-j]+cost for j,cost in chunks[i][axis].items() if j<=k))
                combined=[a+case['weight']*b for a,b in zip(combined,expected)]
            assert prices[axis] == combined
        held = study.get('holdout')
        held_terms, held_cost = [], None
        if held:
            raw = contained(path.parent,held['path']).read_bytes()
            assert hashlib.sha256(raw).hexdigest() == held['sha256']
            terms = parse_terms(raw,len(held['terms']))
            assert terms == [tuple(t) for t in held['terms']]
            assert len(set(terms)) == len(terms) < len(source) and all(t in source for t in terms)
            held_terms = terms
            assert ('elementary_shape' in held) == ('leaf' in held) == ('cost' in held)
            if 'elementary_shape' in held:
                dims = held['elementary_shape']
                assert len(dims)==3 and all(type(d) is int and 1<=d<=4 for d in dims)
                assert study['score_kind']=='fixed-elementary-group-or-pure-axis-upper-bound'
                assert options['holdout_shape']==dims and 'portfolio' not in study
                factor_maps(source,dict(elementary_shape=dims,indices=[source.index(t) for t in terms]))
                assert held['leaf']['shape']==[d*s for d,s in zip(dims,cases[0]['scale'])]
                leaf=snapshot(path.parent,held['leaf'])
                assert type(held['cost']) is int and held['cost']==len(leaf)>0
                held_cost=held['cost']
        assert cover_score(source,prices,held_terms,held_cost) == study['initial_score']
        assert [a['mode'] for a in study['arms']] == ['walk','greedy','anneal']
        for arm in study['arms']:
            expected = options['trials']*options['chunks']*options['steps']
            assert expected == summary['attempts_per_policy'] == int(arm['totals']['attempted'])
            observe = options['observe_every']
            assert int(arm['totals']['observations']) == options['trials']*options['chunks']*((options['steps']+observe-1)//observe)
            assert int(arm['totals']['held_terms']) == (len(held['terms']) if held else 0)
            if held_cost is not None:
                assert int(arm['totals']['held_cost'])==held_cost
            assert not arm['products_materialized'] and 'best_exact_product_rank' not in arm
            assert len(arm['trials']) == options['trials']
            assert not (path.parent/arm['mode']/'products').exists()
            attempts += expected
            scores, identities = [], set()
            for i,trial in enumerate(arm['trials']):
                assert i == trial['trial'] and 'recipe' not in trial and 'exact_product_rank' not in trial
                parent = load(path.parent/arm['mode']/f'trial-{i}.txt',shape,trial['parent']['sha256'])
                end = load(path.parent/arm['mode']/f'end-{i}.txt',shape,trial['end_parent']['sha256'])
                for terms, audit in ((parent,trial['parent']),(end,trial['end_parent'])):
                    assert len(terms) == audit['rank']
                    assert sum(v.bit_count() for t in terms for v in t) == audit['density']
                assert cover_score(parent,prices,held_terms,held_cost) == trial['score'] <= study['initial_score']
                scores.append(trial['score'])
                identities.add(tuple(sorted(parent)))
                winners += 1
                ends += 1
            assert arm['best_score'] == min(scores) and arm['distinct_parents'] == len(identities)
    assert attempts == summary['total_attempts']
    with tempfile.TemporaryDirectory(prefix='metaflip-parent-only-') as directory:
        tmp, tasks = Path(directory), []
        for i,((shape,digest),body) in enumerate(tensors.items()):
            name = f'{i}.txt'
            (tmp/name).write_bytes(body)
            tasks.append((tmp,tensor.Record('x'.join(map(str,shape)),shape,len(body.splitlines()),name,digest)))
        with ProcessPoolExecutor(max_workers=workers,mp_context=multiprocessing.get_context('fork')) as pool:
            checked = list(pool.map(tensor._verify_one,tasks))
    return dict(complete=True,field='GF(2)',record_claim=False,products_materialized=False,
        attempts=attempts,winners=winners,end_states=ends,unique_tensors=len(checked),
        terms=sum(c.terms for c in checked),pair_xors=sum(c.pair_xors for c in checked),
        source_sha256=pins,results=[asdict(c) for c in checked])


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root',type=Path,required=True)
    p.add_argument('--workers',type=int,choices=range(1,5),default=2)
    p.add_argument('--report',type=Path)
    a=p.parse_args()
    result=verify(a.root,a.workers)
    if a.report:
        assert not a.report.exists()
        a.report.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('source_sha256','results')}))
