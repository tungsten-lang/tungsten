#!/usr/bin/env python3
"""Independently replay audited composition/projection compression and tensors."""
import argparse
from concurrent.futures import ProcessPoolExecutor
from dataclasses import asdict
import hashlib
import json
import multiprocessing
from pathlib import Path
import tempfile

from verify_cofactor_mergers import compress_shared
from verify_representation_portfolio import contained, parse_terms
import verify_block_composition_records as tensor


def digest(body):
    return hashlib.sha256(body).hexdigest()


def source_entries(report):
    entries = []
    for row in report['outputs']:
        assert isinstance(row, dict)
        entry = row['result'] if 'result' in row else row
        assert isinstance(entry, dict)
        entries.append(entry)
    return entries


def check_row(job):
    root, row = job
    source = row['input']
    body = contained(root, source['path']).read_bytes()
    assert digest(body) == source['sha256']
    terms = parse_terms(body, row['rank_before'])
    shape = source['shape']
    assert len(shape) == 3 and all(type(n) is int and n > 0 for n in shape)
    width = max(shape[0]*shape[1], shape[1]*shape[2], shape[0]*shape[2])
    assert row['max_bits'] == width
    result, history = compress_shared(terms, max_bits=width)
    assert len(result) == row['rank_after'] and history == row['compression']
    outputs = [source]
    if row['result']:
        assert len(result) < len(terms)
        entry = row['result']
        raw = contained(root, entry['path']).read_bytes()
        assert entry['shape'] == shape and digest(raw) == entry['sha256']
        assert sorted(result) == sorted(parse_terms(raw, len(result)))
        outputs.append(entry)
    else:
        assert not history and sorted(terms) == sorted(result)
    return outputs


def verify(root, workers=2):
    root = Path(root).resolve()
    raw = (root/'report.json').read_bytes()
    report = json.loads(raw)
    assert report['complete'] and report['field'] == 'GF(2)' and not report['record_claim']
    assert not report['canonical_archive_changed'] and not report['redistribution_cleared']
    prior_raw = (root/'source-report.json').read_bytes()
    audit_raw = (root/'source-audit.json').read_bytes()
    assert digest(prior_raw) == report['source_report_sha256']
    assert digest(audit_raw) == report['source_audit_sha256']
    prior, audit = json.loads(prior_raw), json.loads(audit_raw)
    assert prior['complete'] and audit['complete'] and audit['report_sha256'] == digest(prior_raw)
    assert prior['field'] == audit['field'] == 'GF(2)'
    assert not prior['record_claim'] and not audit['record_claim']
    expected = {(tuple(e['shape']), e['sha256']): e for e in source_entries(prior)}
    assert len(expected) == len(prior['outputs']) == report['inputs'] == len(report['rows'])
    seen = set()
    for row in report['rows']:
        source, copied = row['source'], row['input']
        key = tuple(source['shape']), source['sha256']
        assert key not in seen and expected[key] == source
        seen.add(key)
        assert audit['source_sha256'][source['path']] == source['sha256']
        original = contained(root, copied['path']).read_bytes()
        assert copied['shape'] == source['shape']
        assert digest(original) == copied['sha256'] == source['sha256']
        assert row['rank_before'] == int(original.splitlines()[0])
        if 'rank' in source:
            assert type(source['rank']) is int and source['rank'] == row['rank_before']
    pins, tensors = {}, {}
    with ProcessPoolExecutor(max_workers=workers, mp_context=multiprocessing.get_context('fork')) as pool:
        for i, entries in enumerate(pool.map(check_row, ((root, r) for r in report['rows'])), 1):
            for e in entries:
                pins[e['path']] = e['sha256']
                tensors[tuple(e['shape']), e['sha256']] = e
            if i % 8 == 0:
                print(json.dumps(dict(compressions_replayed=i, total=report['inputs'])), flush=True)
    assert report['changed'] == sum(r['result'] is not None for r in report['rows'])
    assert report['rank_saved'] == sum(r['rank_before']-r['rank_after'] for r in report['rows'])
    with tempfile.TemporaryDirectory(prefix='metaflip-product-compression-replay-') as directory:
        tmp = Path(directory);jobs = []
        for i, e in enumerate(tensors.values()):
            body = contained(root, e['path']).read_bytes()
            terms = parse_terms(body, int(body.splitlines()[0]))
            encoded = ''.join('R '+' '.join(map(str, t))+'\n' for t in terms).encode()
            name = str(i)+'.txt';(tmp/name).write_bytes(encoded)
            jobs.append((tmp, tensor.Record('x'.join(map(str, e['shape'])), tuple(e['shape']),
                                            len(terms), name, digest(encoded))))
        with ProcessPoolExecutor(max_workers=workers, mp_context=multiprocessing.get_context('fork')) as pool:
            full = []
            for value in pool.map(tensor._verify_one, jobs):
                full.append(value)
                if len(full) % 8 == 0:
                    print(json.dumps(dict(tensors_verified=len(full), total=len(jobs))), flush=True)
    return dict(complete=True, field='GF(2)', record_claim=False, report_sha256=digest(raw),
                inputs=report['inputs'], changed=report['changed'], rank_saved=report['rank_saved'],
                tensors=len(full), terms=sum(x.terms for x in full), pair_xors=sum(x.pair_xors for x in full),
                source_sha256=pins, results=[asdict(x) for x in full])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path)
    parser.add_argument('--workers', type=int, choices=range(1, 5), default=2)
    args = parser.parse_args()
    result = verify(args.root, args.workers)
    output = args.root/'independent-audit.json'
    assert not output.exists()
    output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('source_sha256', 'results')}))
