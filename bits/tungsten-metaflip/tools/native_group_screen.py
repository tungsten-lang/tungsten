#!/usr/bin/env python3
"""Bounded native intake screen against a frozen parent/price corpus.

Parents and leaves are fully verified; output prices are not rank records.
Any cheaper-than-retained result still needs full expansion and independent
tensor verification. Temporary queues are removed, not left running.
"""
import argparse
from collections import Counter
from hashlib import sha256
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

BIT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BIT/'spec'))
from composition_queue_test import RUNTIME, read_record, store, value
from group_composition_parity_test import bank, plan
from packed_composition_parity_test import exact, parse_terms


def screen(binary, parents_path, prices_path, limit):
    raw_parents = parents_path.read_bytes(); raw_prices = prices_path.read_bytes()
    corpus = json.loads(raw_parents); prices = json.loads(raw_prices)
    retained = {tuple(sorted(s)):r['rank'] for s,r in zip(prices['model_shapes'],prices['baseline_recipes'])}
    assert corpus['complete'] and prices['complete']
    report = {'complete':False, 'field':'GF(2)', 'record_claim':False,
              'scope':'fixed-axis groups up to six, scales 2..4; frozen retained comparator',
              'sha256':{'parents':sha256(raw_parents).hexdigest(), 'prices':sha256(raw_prices).hexdigest(),
                        'binary':sha256(binary.read_bytes()).hexdigest()},
              'parents':0, 'unsupported_parents':0, 'duplicate_parents':0,
              'recipes':0, 'strict_pair_improvements':[], 'cheaper_than_retained':[]}
    seen = set(); banks = {}
    with tempfile.TemporaryDirectory(prefix='metaflip-native-group-screen-') as d:
        root = Path(d); (root/'objects').mkdir()
        for item in corpus['parents'][:limit]:
            shape = tuple(item['shape'])
            if min(shape) < 1 or max(a*b for a,b in ((shape[0],shape[1]),(shape[1],shape[2]),(shape[0],shape[2]))) > 63:
                report['unsupported_parents'] += 1
                continue
            raw = Path(item['path']).read_bytes()
            assert sha256(raw).hexdigest() == item['sha256']
            terms = sorted(parse_terms(raw,item['rank'])); exact(shape,terms)
            key = store(root,shape,terms)
            if key in seen:
                report['duplicate_parents'] += 1
                continue
            seen.add(key)
            before = value(root/'composition/submitted')
            p = subprocess.run([str(binary),'--prepare',str(root),str(RUNTIME),key],
                               env=dict(os.environ,METAFLIP_COMPOSITION_GROUPS='1'),
                               capture_output=True,text=True,timeout=60)
            assert p.returncode == 0, (item['path'],p.stdout,p.stderr)
            after = value(root/'composition/submitted')
            assert after-before <= 9
            report['parents'] += 1; report['recipes'] += after-before
            for ticket in range(before+1,after+1):
                fields = read_record(root/'composition','tasks',ticket).decode().split()
                axis,scale = map(int,fields[3:5]); target = tuple(map(int,fields[5:8]))
                price = int(fields[8]); pairs = sum(c//2 for c in Counter(t[axis] for t in terms).values())
                pair_price = (len(terms)-2*pairs)*scale*scale+pairs*{2:7,3:15,4:26}[scale]
                if fields[0] == 'MCG1':
                    if fields[2] not in banks: banks[fields[2]] = bank(root,fields[2],scale)
                    independent,_ = plan(terms,axis,{k:len(v) for k,v in banks[fields[2]].items()})
                    assert price == independent <= pair_price
                else:
                    assert fields[0] == 'MFC1' and price == pair_price
                row = {'parent':key, 'source':item['path'], 'shape':list(shape), 'rank':len(terms),
                       'axis':axis, 'scale':scale, 'target':list(target), 'price':price,
                       'pair_price':pair_price, 'retained':retained.get(tuple(sorted(target)))}
                if price < pair_price: report['strict_pair_improvements'].append(row)
                if row['retained'] is not None and price < row['retained']:
                    report['cheaper_than_retained'].append(row)
    report['complete'] = True
    report['selected_parent_count'] = min(limit,len(corpus['parents']))
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary',type=Path)
    parser.add_argument('parents',type=Path)
    parser.add_argument('prices',type=Path)
    parser.add_argument('--limit',type=int,default=512)
    parser.add_argument('--output',type=Path,required=True)
    args = parser.parse_args()
    if not 1 <= args.limit <= 512: parser.error('--limit must be 1..512')
    report = screen(args.binary.resolve(),args.parents,args.prices,args.limit)
    args.output.write_text(json.dumps(report,sort_keys=True,indent=2)+'\n')
    print(json.dumps({k:len(v) if isinstance(v,list) else v for k,v in report.items() if k != 'sha256'},sort_keys=True))
