#!/usr/bin/env python3
"""Check a frozen multi-stage cofactor study, including deliberate corruption.

Search-family completeness is limited to each explicitly retained proposal
pool. Reference pages are comparisons, not a global novelty certificate.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re
import tempfile

from verify_cofactor_mergers import verify
from verify_representation_portfolio import contained, parse_terms
from verify_block_composition_records import Record, _verify_one


def audit(root, workers=2):
    root = root.resolve()
    report = json.loads((root/'report.json').read_text())
    assert report['complete'] and not report['record_claim'] and not report['redistribution_cleared']
    for name, digest in report['retained_files'].items():
        assert hashlib.sha256(contained(root, name).read_bytes()).hexdigest() == digest, name
    outputs = {}
    all_endpoints = {}
    for name in report['studies']:
        base = contained(root, name)
        data = json.loads((base/'report.json').read_text())
        for row in data['rows']:
            for case in row['cases']:
                entry = case['result']
                all_endpoints[name+'/'+entry['path']] = (row['target'], case['rank'], case['density'], entry['sha256'])
        outputs[name] = verify(base, workers)
    mutations = []
    with tempfile.TemporaryDirectory(prefix='metaflip-cofactor-corruption-') as directory:
        temporary = Path(directory)
        for index, winner in enumerate(report['best']):
            target, rank, density, digest = all_endpoints[winner['result']['path']]
            assert (target, rank, density, digest) == (
                winner['target'], winner['rank'], winner['density'], winner['result']['sha256'])
            assert rank == min(r for t, r, _, _ in all_endpoints.values() if t == target)
            raw = contained(root, winner['result']['path']).read_bytes()
            terms = parse_terms(raw, rank)
            assert hashlib.sha256(raw).hexdigest() == digest
            # Keep the declared rank and domain valid; change one output bit
            # and recompute the file hash. Rejection must be algebraic, not a
            # stale-hash or malformed-file guard.
            first = list(terms[0])
            width = target[0]*target[2]
            bit = next(i for i in range(width) if first[2] ^ (1 << i))
            first[2] ^= 1 << bit
            terms[0] = tuple(first)
            body = ''.join('R '+' '.join(map(str, t))+'\n' for t in terms).encode()
            filename = f'{index}.txt'
            (temporary/filename).write_bytes(body)
            try:
                _verify_one((temporary, Record('x'.join(map(str, target)), tuple(target), rank,
                                              filename, hashlib.sha256(body).hexdigest())))
            except ValueError as error:
                assert 'tensor' in str(error)
                mutations.append(dict(target=target, rejected=True, reason=str(error)))
            else:
                raise AssertionError('corrupted full tensor was admitted')
    for reference in report['references']:
        raw = contained(root, reference['path']).read_text()
        match = re.search(r'<h1>Description of fast matrix multiplication algorithm:.*?:([0-9]+)&rang;', raw)
        assert match and int(match[1]) == reference['listed_rank']
    return dict(schema=1, complete=True, field='GF(2)', record_claim=False,
        studies={name: {k: v for k, v in result.items() if k != 'results'} for name, result in outputs.items()},
        stage_tensor_checks=sum(r['tensors'] for r in outputs.values()),
        proposal_pair_checks=sum(r['totals']['possible_pairs'] for r in outputs.values()),
        unique_proposals_per_stage=sum(r['totals']['unique_proposals_replayed'] for r in outputs.values()),
        local_rank_gains=[w for w in report['best'] if w['rank'] < w['previous_local_rank']],
        deliberate_corruption_checks=mutations)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--workers', type=int, choices=range(1, 5), default=2)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = audit(args.root, args.workers)
    if args.report:
        args.report.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'studies'}))
