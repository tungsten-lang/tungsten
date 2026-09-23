#!/usr/bin/env python3
"""Screen and exactly materialize block extensions of certified GF(2) tensors.

Lille ranks are dated comparison data, not tensor witnesses or novelty proofs.
Only retained certificates and exactly replayed portfolio tensors supply sources.
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
import tempfile

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from check_wide_rectangular_closure import CANDIDATES, CERTS, MANIFEST

ROOT = HERE.parents[2]
sys.path[:0] = [str(ROOT / 'benchmarks/matmul/metaflip'),
                str(ROOT / 'bits/tungsten-metaflip/spec')]
from packed_composition_parity_test import exact  # noqa: E402
from verify_cofactor_mergers import compress_shared, orient  # noqa: E402
from verify_composition_targets import block, naive  # noqa: E402
from wide_matrix_cleanup_parity_test import blob, read_blob  # noqa: E402


def screen(entries, candidates=CANDIDATES, max_dim=32, portfolio_rows=()):
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
    provenance = {}
    for shape, name, rank, digest, compressed in candidates:
        key = tuple(sorted(shape))
        row = (rank, name, digest, compressed)
        if key not in seeds or row[:2] < seeds[key][:2]:
            seeds[key] = row
            provenance[key] = None
    for entry in portfolio_rows:
        key = tuple(entry['shape'])
        if len(key) != 3 or tuple(sorted(key)) != key:
            raise ValueError(f'invalid portfolio shape: {key}')
        rank = entry['rank']
        if type(rank) is not int or rank < 1:
            raise ValueError(f'invalid portfolio rank: {entry!r}')
        if key not in seeds or rank < seeds[key][0]:
            seeds[key] = (rank, 'x'.join(map(str, entry['result_shape'])),
                          entry['result_sha256'], False)
            provenance[key] = key
    missing = sorted(set(seeds) - set(public))
    if missing:
        raise ValueError(f'public digest missing {len(missing)} seed shapes: {missing[:8]}')

    proposals = {}
    oriented = {}
    for shape, (rank, name, digest, compressed) in seeds.items():
        for orientation in set(itertools.permutations(shape)):
            for axis in range(3):
                group = (axis, tuple(orientation[i] for i in range(3) if i != axis))
                oriented.setdefault(group, []).append((orientation, shape))
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
                    if provenance[shape] is not None:
                        row['seed_source'] = 'portfolio'
                        row['portfolio_shape'] = list(provenance[shape])
                    choice = (cost, operation, orientation, axis, name)
                    if key not in proposals or choice < proposals[key][0]:
                        proposals[key] = choice, row
    for (axis, _), members in oriented.items():
        members = sorted(set(members), key=lambda item: (item[0][axis], item[0], item[1]))
        for (left_orientation, left_shape), (right_orientation, right_shape) in itertools.combinations(members, 2):
            if left_shape == right_shape:
                continue  # doubling an existing certificate is already screened above
            target = list(left_orientation)
            target[axis] += right_orientation[axis]
            if max(target) > max_dim:
                continue
            key = tuple(sorted(target))
            if key in seeds or key not in public:
                continue
            left_rank, left_name, left_digest, left_compressed = seeds[left_shape]
            right_rank, right_name, right_digest, right_compressed = seeds[right_shape]
            cost = left_rank + right_rank
            if cost >= public[key]:
                continue
            row = dict(shape=list(key), rank=cost, public_rank=public[key],
                       gap=public[key] - cost, operation='pair',
                       orientation=list(left_orientation),
                       right_orientation=list(right_orientation), axis=axis,
                       seed_shape=left_name, seed_rank=left_rank,
                       seed_sha256=left_digest, compressed=left_compressed,
                       right_seed_shape=right_name, right_seed_rank=right_rank,
                       right_seed_sha256=right_digest, right_compressed=right_compressed)
            if provenance[left_shape] is not None:
                row['seed_source'] = 'portfolio'
                row['portfolio_shape'] = list(provenance[left_shape])
            if provenance[right_shape] is not None:
                row['right_seed_source'] = 'portfolio'
                row['right_portfolio_shape'] = list(provenance[right_shape])
            choice = (cost, 'pair', left_orientation, axis, left_name, right_name)
            if key not in proposals or choice < proposals[key][0]:
                proposals[key] = choice, row
    return sorted((row for _, row in proposals.values()),
                  key=lambda row: (-row['gap'], row['shape']))


def load_seed(row, replay_root=None, prefix=''):
    name, rank = row[prefix + 'seed_shape'], row[prefix + 'seed_rank']
    if row.get(prefix + 'seed_source') == 'portfolio':
        if replay_root is None:
            raise ValueError('portfolio source requires an exact replay directory')
        key = 'x'.join(map(str, row[prefix + 'portfolio_shape']))
        path = replay_root / key / f'{name}.mfw'
        raw = path.read_bytes()
    else:
        suffix = '.mfw.gz.b64' if row[prefix + 'compressed'] else '.mfw'
        path = CERTS / f'{name}-r{rank}{suffix}'
        raw = path.read_bytes()
        if row[prefix + 'compressed']:
            raw = gzip.decompress(base64.b64decode(raw.replace(b'\n', b''), validate=True))
        if hashlib.sha256(raw).hexdigest() != row[prefix + 'seed_sha256']:
            raise ValueError(f'seed digest mismatch: {path}')
    source_shape, source_terms = read_blob(raw)
    if source_shape != tuple(map(int, name.split('x'))) or len(source_terms) != rank:
        raise ValueError(f'seed shape or rank mismatch: {path}')
    if row.get(prefix + 'seed_source') == 'portfolio':
        body = str(rank) + '\n' + ''.join(' '.join(map(str, term)) + '\n'
                                          for term in source_terms)
        if hashlib.sha256(body.encode('ascii')).hexdigest() != row[prefix + 'seed_sha256']:
            raise ValueError(f'portfolio result digest mismatch: {path}')
    exact(source_shape, source_terms)
    return source_shape, source_terms


def materialize(row, output_dir, replay_root=None):
    source_shape, source_terms = load_seed(row, replay_root)

    orientation = tuple(row['orientation'])
    axis = row['axis']
    target = list(orientation)
    if row['operation'] == 'pair':
        right_orientation = tuple(row['right_orientation'])
        if any(orientation[i] != right_orientation[i] for i in range(3) if i != axis):
            raise ValueError('pair has incompatible fixed dimensions')
        target[axis] += right_orientation[axis]
    else:
        target[axis] += 1 if row['operation'] == 'append' else target[axis]
    target = tuple(target)
    if tuple(sorted(target)) != tuple(row['shape']):
        raise ValueError('target orientation mismatch')
    aligned = orient(source_shape, source_terms, orientation)
    left = block(orientation, aligned, target, (0, 0, 0))
    right_shape = list(target)
    right_shape[axis] -= orientation[axis]
    right_shape = tuple(right_shape)
    if row['operation'] == 'append':
        right = naive(right_shape)
    elif row['operation'] == 'double':
        right = aligned
    elif row['operation'] == 'pair':
        right_source_shape, right_source_terms = load_seed(row, replay_root, 'right_')
        right = orient(right_source_shape, right_source_terms, right_orientation)
    else:
        raise ValueError(f'unknown operation: {row["operation"]}')
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
    parser.add_argument('--include-portfolio', action='store_true',
                        help='also replay exact structured-parent portfolio seeds')
    args = parser.parse_args()
    digest = json.loads(args.digest.read_text())
    portfolio_rows = json.loads(MANIFEST.read_text())['rows'] if args.include_portfolio else ()
    rows = screen(digest['entries'], portfolio_rows=portfolio_rows)
    if args.output_dir is not None:
        args.output_dir.mkdir(parents=True, exist_ok=False)
        selected = sorted({'x'.join(map(str, row[prefix + 'portfolio_shape']))
                           for row in rows for prefix in ('', 'right_')
                           if row.get(prefix + 'seed_source') == 'portfolio'})
        if selected:
            with tempfile.TemporaryDirectory(prefix='metaflip-portfolio-replay-') as tmp:
                replay_root = Path(tmp) / 'sources'
                command = ['ruby', str(HERE / 'replay_structured_parent_portfolio.rb'),
                           '--output', str(replay_root)]
                for name in selected:
                    command.extend(('--only', name))
                subprocess.run(command, check=True, capture_output=True, text=True)
                rows = [materialize(row, args.output_dir, replay_root) for row in rows]
        else:
            rows = [materialize(row, args.output_dir) for row in rows]
    print(json.dumps(dict(source=digest.get('source'), created_at=digest.get('createdAt'),
                          field='GF(2)', record_claim=False, rows=rows), indent=2))


if __name__ == '__main__':
    main()
