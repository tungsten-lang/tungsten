#!/usr/bin/env python3
"""Screen and exactly materialize one-step extensions of certified GF(2) tensors.

Lille ranks are dated comparison data, not tensor witnesses or novelty proofs.
Only the retained CANDIDATES certificates supply nontrivial source tensors.
"""
import argparse
import base64
import gzip
import hashlib
import itertools
import json
from pathlib import Path
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from check_wide_rectangular_closure import CANDIDATES, CERTS

ROOT = HERE.parents[2]
sys.path[:0] = [str(ROOT / 'benchmarks/matmul/metaflip'),
                str(ROOT / 'bits/tungsten-metaflip/spec')]
from packed_composition_parity_test import exact  # noqa: E402
from verify_cofactor_mergers import compress_shared, orient  # noqa: E402
from verify_composition_targets import block, naive  # noqa: E402
from wide_matrix_cleanup_parity_test import blob, read_blob  # noqa: E402


def screen(entries, candidates=CANDIDATES, max_dim=32):
    public = {}
    for entry in entries:
        shape = entry['format']
        rank = entry['rank']
        if (len(shape) != 3 or any(type(n) is not int or n < 1 for n in shape)
                or type(rank) is not int or rank < 1):
            raise ValueError(f'invalid public rank: {entry!r}')
        key = tuple(sorted(shape))
        if key in public and public[key] != rank:
            raise ValueError(f'conflicting public rank for {key}')
        public[key] = rank

    seeds = {}
    for shape, name, rank, digest, compressed in candidates:
        key = tuple(sorted(shape))
        row = (rank, name, digest, compressed)
        if key not in seeds or row[:2] < seeds[key][:2]:
            seeds[key] = row
    missing = sorted(set(seeds) - set(public))
    if missing:
        raise ValueError(f'public digest missing {len(missing)} seed shapes: {missing[:8]}')

    proposals = {}
    for shape, (rank, name, digest, compressed) in seeds.items():
        for orientation in set(itertools.permutations(shape)):
            for axis in range(3):
                for operation in ('append', 'double'):
                    target = list(orientation)
                    target[axis] += 1 if operation == 'append' else target[axis]
                    if max(target) > max_dim:
                        continue
                    key = tuple(sorted(target))
                    if key in seeds or key not in public:
                        continue
                    cost = rank + (target[(axis + 1) % 3] * target[(axis + 2) % 3]
                                   if operation == 'append' else rank)
                    if cost >= public[key]:
                        continue
                    row = dict(shape=list(key), rank=cost, public_rank=public[key],
                               gap=public[key] - cost, operation=operation,
                               orientation=list(orientation), axis=axis,
                               seed_shape=name, seed_rank=rank,
                               seed_sha256=digest, compressed=compressed)
                    choice = (cost, operation, orientation, axis, name)
                    if key not in proposals or choice < proposals[key][0]:
                        proposals[key] = choice, row
    return sorted((row for _, row in proposals.values()),
                  key=lambda row: (-row['gap'], row['shape']))


def materialize(row, output_dir):
    name, rank = row['seed_shape'], row['seed_rank']
    suffix = '.mfw.gz.b64' if row['compressed'] else '.mfw'
    path = CERTS / f'{name}-r{rank}{suffix}'
    raw = path.read_bytes()
    if row['compressed']:
        raw = gzip.decompress(base64.b64decode(raw.replace(b'\n', b''), validate=True))
    if hashlib.sha256(raw).hexdigest() != row['seed_sha256']:
        raise ValueError(f'seed digest mismatch: {path}')
    source_shape, source_terms = read_blob(raw)
    if source_shape != tuple(map(int, name.split('x'))) or len(source_terms) != rank:
        raise ValueError(f'seed shape or rank mismatch: {path}')
    exact(source_shape, source_terms)

    orientation = tuple(row['orientation'])
    axis = row['axis']
    target = list(orientation)
    target[axis] += 1 if row['operation'] == 'append' else target[axis]
    target = tuple(target)
    if tuple(sorted(target)) != tuple(row['shape']):
        raise ValueError('target orientation mismatch')
    aligned = orient(source_shape, source_terms, orientation)
    left = block(orientation, aligned, target, (0, 0, 0))
    right_shape = list(target)
    right_shape[axis] -= orientation[axis]
    right_shape = tuple(right_shape)
    right = naive(right_shape) if row['operation'] == 'append' else aligned
    offsets = [0, 0, 0]
    offsets[axis] = orientation[axis]
    terms = left + block(right_shape, right, target, offsets)
    if len(terms) != row['rank']:
        raise ValueError('planned block rank mismatch')
    width = max(target[0] * target[1], target[1] * target[2], target[0] * target[2])
    terms, history = compress_shared(terms, max_bits=width)
    exact(target, terms)
    output = output_dir / ('x'.join(map(str, target)) + f'-r{len(terms)}.mfw')
    if output.exists():
        raise FileExistsError(output)
    output.write_bytes(blob(target, terms))
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    checked = json.loads(subprocess.check_output(
        ['ruby', str(ROOT / 'bits/tungsten-metaflip/tools/verify_tensor.rb'),
         '--shape', 'x'.join(map(str, target)), str(output)], text=True))[0]
    if not checked['exact'] or checked['rank'] != len(terms) or checked['sha256'] != digest:
        raise ValueError(f'independent tensor verification failed: {output}')
    return dict(row, rank=len(terms), planned_rank=row['rank'],
                gap=row['public_rank'] - len(terms), sha256=digest,
                cleanup_steps=len(history), output=str(output))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('digest', type=Path, help='external fmm_sota.json')
    parser.add_argument('--output-dir', type=Path,
                        help='new directory for independently verified MFW1 tensors')
    args = parser.parse_args()
    digest = json.loads(args.digest.read_text())
    rows = screen(digest['entries'])
    if args.output_dir is not None:
        args.output_dir.mkdir(parents=True, exist_ok=False)
        rows = [materialize(row, args.output_dir) for row in rows]
    print(json.dumps(dict(source=digest.get('source'), created_at=digest.get('createdAt'),
                          field='GF(2)', record_claim=False, rows=rows), indent=2))


if __name__ == '__main__':
    main()
