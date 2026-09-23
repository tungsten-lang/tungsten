#!/usr/bin/env python3
"""Materialize audited block-47 formulas and retain exact cancellations."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
AUDIT = ROOT / 'benchmarks/matmul/metaflip/block_composition_cross_audit.tsv'
RECORDS = ROOT / 'benchmarks/matmul/metaflip/block_composition_records.tsv'
CERTS = HERE / 'certificates/block47-exact-20260923/manifest.json'
sys.path[:0] = [str(ROOT / 'bits/tungsten-metaflip/spec'),
                str(ROOT / 'benchmarks/matmul/metaflip')]
from wide_matrix_cleanup_parity_test import blob  # noqa: E402
from verify_representation_portfolio import parse_terms  # noqa: E402


def scan(composer, leaf_root, output_dir, targets=(), limit=None):
    formulas = list(csv.DictReader(AUDIT.open(), delimiter='\t'))
    by_target = {row['target']: row for row in formulas}
    if targets:
        rows = [by_target[target] for target in targets]
    else:
        materialized = {row['target'] for row in csv.DictReader(
            RECORDS.open(), delimiter='\t')}
        materialized.update('x'.join(map(str, row['shape'])) for row in
                            json.loads(CERTS.read_text())['rows'])
        rows = sorted((row for row in formulas if row['target'] not in materialized
                       and int(row['audited_gain']) > 0),
                      key=lambda row: (-int(row['audited_gain']), row['target']))[:limit]
    output_dir.mkdir(parents=True, exist_ok=True)
    retained = []
    for row in rows:
        shape = row['target']
        text_path = output_dir / f'{shape}.txt'
        result = subprocess.run([str(composer), shape, str(text_path),
                                 '--leaf-root', str(leaf_root)], check=True,
                                capture_output=True, text=True, timeout=120)
        formula_match = re.search(r'^formula rank (\d+)$', result.stdout, re.M)
        exact_match = re.search(r'^exact rank (\d+) ->', result.stdout, re.M)
        if (formula_match is None or exact_match is None or
                int(formula_match.group(1)) != int(row['formula_rank'])):
            raise ValueError(f'formula replay mismatch: {shape}')
        rank = int(exact_match.group(1))
        report = {'shape': shape, 'formula_rank': int(row['formula_rank']),
                  'exact_rank': rank, 'cancellations': int(row['formula_rank']) - rank}
        if rank < int(row['formula_rank']):
            verified = json.loads(subprocess.check_output(
                ['ruby', str(HERE / 'verify_tensor.rb'), '--shape', shape,
                 str(text_path)], text=True))[0]
            if not verified['exact'] or verified['rank'] != rank:
                raise ValueError(f'independent tensor check failed: {shape}')
            tensor = blob(tuple(map(int, shape.split('x'))),
                          parse_terms(text_path.read_bytes(), rank))
            tensor_path = output_dir / f'{shape}-r{rank}.mfw'
            if tensor_path.exists():
                raise FileExistsError(tensor_path)
            tensor_path.write_bytes(tensor)
            report['sha256'] = hashlib.sha256(tensor).hexdigest()
            packed_check = json.loads(subprocess.check_output(
                ['ruby', str(HERE / 'verify_tensor.rb'), '--shape', shape,
                 str(tensor_path)], text=True))[0]
            if (not packed_check['exact'] or packed_check['rank'] != rank or
                    packed_check['sha256'] != report['sha256']):
                raise ValueError(f'packed tensor check failed: {shape}')
            report['mfw'] = str(tensor_path)
            retained.append(report)
        text_path.unlink()
        print(json.dumps(report), flush=True)
    return retained


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--composer', required=True, type=Path)
    parser.add_argument('--leaf-root', required=True, type=Path)
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--target', action='append', default=[])
    parser.add_argument('--limit', type=int)
    args = parser.parse_args()
    if not args.target and (args.limit is None or args.limit < 1):
        parser.error('provide --target or a positive --limit')
    scan(args.composer, args.leaf_root, args.output_dir, args.target, args.limit)
