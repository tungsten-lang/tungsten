#!/usr/bin/env python3
"""Conservative reference closure including reported parent templates.

Unlike a block/Kronecker-only comparison, this reuses every reported smaller
parent structure at all bounded scales. Parent coefficient fields are not
reverified here: these prices are comparison data, NEVER tensor certificates.
"""
import argparse
from collections import defaultdict
import hashlib
from itertools import product
import json
import math
from pathlib import Path
import re

from verify_recursive_portfolio import catalog_minima, solver


def templates(wide, maximum=32):
    families = set()
    for tag, row in wide.items():
        parent = tuple(row['s1']['dimension'])
        scale = row['s2']['dimension']
        assert len(parent) == len(scale) == 3
        assert all(type(n) is int and n > 0 for n in parent + tuple(scale))
        assert sorted(a*b for a,b in zip(parent,scale)) == sorted(map(int,tag.split('x')))
        terms = []
        for piece in row['s1']['structure'].split('+'):
            match = re.fullmatch(r'\s*(\d*)\s*<\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*>\s*',piece)
            assert match, 'unsupported reported structure'
            count = int(match[1] or 1)
            shape = tuple(int(match[i]) for i in (2,3,4))
            assert count > 0 and min(shape) > 0
            terms.append((count,shape))
        assert sum(n*math.prod(s) for n,s in terms) == row['s1']['rank']
        assert all(math.prod(s) < math.prod(parent) for _,s in terms)
        families.add((parent,tuple(terms)))
    expressions = defaultdict(set)
    for parent, terms in families:
        for scale in product(*(range(1,maximum//d+1) for d in parent)):
            target = tuple(sorted(a*b for a,b in zip(parent,scale)))
            expanded = defaultdict(int)
            for count, shape in terms:
                leaf = tuple(sorted(a*b for a,b in zip(shape,scale)))
                if max(leaf) > maximum:
                    break
                expanded[leaf] += count
            else:
                expressions[target].add(tuple(sorted((count,leaf) for leaf,count in expanded.items())))
    return dict(expressions), len(families)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('baseline','catalog','wide','candidates','output'):
        p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--references',type=Path,action='append',default=[])
    args = p.parse_args()
    assert not args.output.exists()
    pins = {}
    def read(path):
        raw = path.read_bytes()
        pins[str(path.resolve())] = hashlib.sha256(raw).hexdigest()
        return json.loads(raw)
    base, catalog, wide, candidates = map(read,(args.baseline,args.catalog,args.wide,args.candidates))
    assert base['complete'] and base['field']=='GF(2)' and not base['record_claim']
    assert candidates['complete'] and not candidates['record_claim']
    known = {tuple(r['shape']):r['augmented_rank'] for r in base['rows']}
    def add(shape,rank):
        key = tuple(sorted(shape))
        known[key] = min(known.get(key,rank),rank)
    for shape,rank in catalog_minima(catalog).items():
        add(shape,rank)
    for tag,row in wide.items():
        add(tuple(map(int,tag.split('x'))),row['serendipitous_rank'])
    for path in args.references:
        ref = read(path)
        assert ref['complete'] and not ref['record_claim']
        for row in ref['rows']:
            if row.get('listed_rank') is not None:
                add(row['shape'],row['listed_rank'])
    edges, families = templates(wide,base['maximum'])
    plain, rich = solver(known), solver(known,edges)
    rows = []
    for row in candidates.get('outputs',candidates.get('rows',[])):
        if 'outputs' not in candidates and row.get('gain',0) <= 0:
            continue
        shape = tuple(row.get('target',row.get('shape')))
        rank = row.get('rank',row.get('augmented_rank'))
        before, after = plain(shape), rich(shape)
        assert after <= before
        rows.append(dict(shape=shape,rank=rank,block_kronecker_reference=before,
            reported_template_reference=after,below_reference=rank<after))
    report = dict(complete=True,record_claim=False,comparison_only=True,
        parent_fields_not_all_reverified=True,maximum=base['maximum'],
        family='axis blocks, Kronecker products, and recursively repriced reported parent templates',
        templates=families,targets_with_templates=len(edges),expressions=sum(map(len,edges.values())),
        below_reference=sum(r['below_reference'] for r in rows),source_sha256=pins,rows=rows)
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k not in ('source_sha256','rows')}))
    print(json.dumps([r for r in rows if r['below_reference']]))


if __name__=='__main__':
    main()
