#!/usr/bin/env python3
"""Independently verify three materialized block-47 GF(2) tensors."""
import argparse
import base64
import csv
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
CERTS = HERE / 'certificates/block47-exact-20260923'
MANIFEST = CERTS / 'manifest.json'
AUDIT = ROOT / 'benchmarks/matmul/metaflip/block_composition_cross_audit.tsv'
SOURCES = ROOT / 'benchmarks/matmul/metaflip/block_composition_cross_audit_sources.tsv'
sys.path[:0] = [str(HERE), str(ROOT / 'bits/tungsten-metaflip/spec')]
from wide_matrix_cleanup_parity_test import read_blob  # noqa: E402
from wide_matrix_cleanup_parity_test import blob  # noqa: E402
from packed_composition_parity_test import exact  # noqa: E402
sys.path.insert(0, str(ROOT / 'benchmarks/matmul/metaflip'))
from verify_representation_portfolio import parse_terms  # noqa: E402


def decode(path, expected_sha256):
    compressed = base64.b64decode(path.read_bytes().replace(b'\n', b''),
                                  validate=True)
    payload = gzip.decompress(compressed)
    if hashlib.sha256(payload).hexdigest() != expected_sha256:
        raise ValueError(f'certificate digest mismatch: {path.name}')
    return payload


def check(replay_walk=None, replay_compose=None, leaf_root=None):
    manifest = json.loads(MANIFEST.read_text())
    if (manifest['schema'] != 1 or manifest['field'] != 'GF(2)' or
            manifest['record_claim'] is not False):
        raise ValueError('invalid certificate manifest')
    for path, key in ((AUDIT, 'formula_audit_sha256'),
                      (SOURCES, 'formula_source_revisions_sha256')):
        if hashlib.sha256(path.read_bytes()).hexdigest() != manifest[key]:
            raise ValueError(f'source revision changed: {path}')
    formulas = {row['target']: row for row in csv.DictReader(
        AUDIT.open(), delimiter='\t')}
    results = []
    with tempfile.TemporaryDirectory(prefix='metaflip-block47-exact-') as temp:
        for row in manifest['rows']:
            shape = tuple(row['shape'])
            name = 'x'.join(map(str, shape))
            formula = formulas[name]
            if (int(formula['formula_rank']) != row['formula_rank'] or
                    int(formula['live_fmm']) != row['listed_rank'] or
                    row['rank'] > row['composed_exact_rank'] or
                    row['composed_exact_rank'] > row['formula_rank'] or
                    row['rank'] >= int(formula['strongest_rank'])):
                raise ValueError(f'formula/comparator mismatch: {name}')
            path = CERTS / f'{name}-r{row["rank"]}.mfw.gz.b64'
            payload = decode(path, row['mfw_sha256'])
            actual_shape, terms = read_blob(payload)
            if actual_shape != shape or len(terms) != row['rank']:
                raise ValueError(f'certificate header mismatch: {name}')
            exact(shape, terms)
            decoded = Path(temp) / f'{name}.mfw'
            decoded.write_bytes(payload)
            verified = json.loads(subprocess.check_output(
                ['ruby', str(HERE / 'verify_tensor.rb'), '--shape', name,
                 str(decoded)], text=True))[0]
            if (not verified['exact'] or verified['rank'] != row['rank'] or
                    verified['sha256'] != row['mfw_sha256']):
                raise ValueError(f'independent tensor check failed: {name}')
            if replay_compose is not None:
                composed = Path(temp) / f'{name}-composed.txt'
                subprocess.run([str(replay_compose), name, str(composed),
                                '--leaf-root', str(leaf_root)], check=True,
                               capture_output=True, text=True)
                composed_terms = parse_terms(composed.read_bytes(),
                                             row['composed_exact_rank'])
                composed_payload = blob(shape, composed_terms)
                expected = row.get('composed_mfw_sha256', row['mfw_sha256'])
                if hashlib.sha256(composed_payload).hexdigest() != expected:
                    raise ValueError(f'composition replay mismatch: {name}')
                exact(shape, composed_terms)
            if 'walk_nonce' in row:
                parent_path = CERTS / f'{name}-r{row["composed_exact_rank"]}-parent.mfw.gz.b64'
                parent = decode(parent_path, row['composed_mfw_sha256'])
                parent_shape, parent_terms = read_blob(parent)
                if parent_shape != shape or len(parent_terms) != row['composed_exact_rank']:
                    raise ValueError(f'walk parent header mismatch: {name}')
                exact(shape, parent_terms)
                parent_decoded = Path(temp) / f'{name}-parent.mfw'
                parent_decoded.write_bytes(parent)
                if replay_walk is not None:
                    replayed = Path(temp) / f'{name}-replayed.mfw'
                    subprocess.run([str(replay_walk), name, str(parent_decoded),
                                    str(replayed), str(row['walk_steps']),
                                    str(row['walk_nonce'])], check=True, capture_output=True,
                                   text=True)
                    if replayed.read_bytes() != payload:
                        raise ValueError(f'walk replay mismatch: {name}')
            results.append({'shape': name, 'rank': row['rank'],
                            'listed_rank': row['listed_rank'],
                            'sha256': row['mfw_sha256']})
    return results


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--replay-walk', type=Path)
    parser.add_argument('--replay-compose', type=Path)
    parser.add_argument('--leaf-root', type=Path)
    args = parser.parse_args()
    if (args.replay_compose is None) != (args.leaf_root is None):
        parser.error('--replay-compose and --leaf-root must be given together')
    print(json.dumps({'field': 'GF(2)', 'record_claim': False,
                      'verified': check(args.replay_walk, args.replay_compose,
                                        args.leaf_root)}, indent=2))
