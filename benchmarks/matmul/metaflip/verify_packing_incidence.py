#!/usr/bin/env python3
"""Independent partition-set check of every proposed packing alias."""
import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path

from verify_representation_portfolio import parse_terms


def verify(report_path, inputs_path):
    raw = report_path.read_bytes()
    report, inputs = json.loads(raw), json.loads(inputs_path.read_bytes())
    assert report['complete'] and report['packing_only'] and not report['record_claim']
    assert inputs['complete'] and inputs['field'] == report['field'] == 'GF(2)'
    assert report['source_sha256'][str(inputs_path.resolve())] == hashlib.sha256(inputs_path.read_bytes()).hexdigest()
    loaded = {}
    def load(index):
        if index not in loaded:
            parent = inputs['parents'][index]
            data = Path(parent['path']).read_bytes()
            assert hashlib.sha256(data).hexdigest() == parent['sha256']
            loaded[index] = parse_terms(data, parent['rank'])
        return loaded[index]
    selected = {i for i, p in enumerate(inputs['parents']) if min(p['shape']) >= 2 and p['rank'] <= report['limits']['max_rank']}
    members, expected = set(), set()
    for group in report['classes']:
        assert group['representative'] in group['members']
        assert group['shape'] == inputs['parents'][group['representative']]['shape']
        assert group['rank'] == inputs['parents'][group['representative']]['rank']
        assert group['touches_new'] == any(i >= report['limits']['new_from'] for i in group['members'])
        for i in group['members']:
            assert i not in members
            members.add(i)
            if i != group['representative']:
                expected.add((group['representative'], i))
    assert members == selected and report['parents'] == report['processed'] == len(selected)
    actual = set()
    for match in report['matches']:
        a, b, permutation = match['source'], match['target'], match['permutation']
        assert (a, b) in expected and (a, b) not in actual
        actual.add((a, b))
        assert inputs['parents'][a]['shape'] == inputs['parents'][b]['shape']
        left, right = load(a), load(b)
        assert len(left) == len(right) == len(permutation)
        assert all(type(i) is int for i in permutation) and sorted(permutation) == list(range(len(left)))
        for axis in range(3):
            lhs, rhs = defaultdict(set), defaultdict(set)
            for i, term in enumerate(left):
                lhs[term[axis]].add(permutation[i])
            for i, term in enumerate(right):
                rhs[term[axis]].add(i)
            assert {frozenset(s) for s in lhs.values()} == {frozenset(s) for s in rhs.values()}
    assert actual == expected
    representatives = [g['representative'] for g in report['classes'] if g['touches_new']]
    assert representatives == report['packing_representatives']
    return dict(complete=True, field='GF(2)', record_claim=False, packing_only=True,
        report_sha256=hashlib.sha256(raw).hexdigest(), matches=len(actual), parents=len(selected),
        representatives=len(report['classes']), touched_representatives=len(representatives),
        tensor_equivalence_claim=False)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--report', type=Path, required=True)
    p.add_argument('--inputs', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    assert not args.output.exists()
    result = verify(args.report, args.inputs)
    args.output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result), flush=True)
