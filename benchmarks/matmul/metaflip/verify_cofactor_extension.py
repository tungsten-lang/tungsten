#!/usr/bin/env python3
"""Replay a retained cofactor extension and its separate constructive DP.

The finite join pools and complete output tensors are checked independently.
The parent-screen shortlist remains a heuristic, not an exhaustive rank bound.
Reference listings are comparisons, not global novelty certificates.
"""
import argparse
import json
from pathlib import Path

from verify_cofactor_audit import audit
from verify_recursive_portfolio import verify as verify_recursive
from verify_representation_portfolio import contained


def verify(root, workers=2):
    root = root.resolve()
    report = json.loads((root / 'report.json').read_text())
    assert report['kind'] == 'cofactor-extension'
    cofactor = audit(root, workers)
    prop = report['propagation']
    base = contained(root, prop['path'])
    recursive = verify_recursive(base, contained(base, prop['admitted']),
                                 root / 'tools/verify_block_composition_records.py', workers)
    assert recursive['dp_shapes'] == prop['shapes']
    assert recursive['improved_shapes'] == prop['improved']
    source = json.loads((base / 'report.json').read_text())
    direct = {tuple(r['snapshot']['shape']) for r in source['basis'] if r['kind'] == 'new'}
    improved = {tuple(r['shape']) for r in source['rows'] if r['gain'] > 0}
    assert len(improved & direct) == prop['direct']
    assert len(improved - direct) == prop['derived']
    for reference in report['references']:
        assert reference['comparison_only'] and reference['field_and_bilinearity_not_reverified']
        assert reference['below_listed'] == (reference['candidate_rank'] < reference['listed_rank'])
    return dict(schema=1, complete=True, field='GF(2)', record_claim=False,
                cofactor=cofactor,
                propagation={k: v for k, v in recursive.items() if k != 'cases'},
                parent_screen_is_heuristic=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--workers', type=int, choices=range(1, 5), default=2)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = verify(args.root, args.workers)
    if args.report:
        args.report.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(dict(complete=result['complete'],
                         stage_tensor_checks=result['cofactor']['stage_tensor_checks'],
                         proposal_pair_checks=result['cofactor']['proposal_pair_checks'],
                         propagation=result['propagation'],
                         new_local_gains=result['cofactor']['local_rank_gains'])))
