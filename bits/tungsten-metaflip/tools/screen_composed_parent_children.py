#!/usr/bin/env python3
"""Project verified top-two tensors, including their composed parent.

The public table is numerical comparison data, not an exact tensor witness.
Every admitted child is rebuilt from pinned parents and checked in full.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import screen_top_two_projection_children as top
from screen_structured_parent_projections import project_grid

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def build_parents(source_root, output_dir):
    data = json.loads(top.KNOWN_MANIFEST.read_text())
    top.replay_sources(source_root,
                       (row['source_portfolio_shape'] for row in data['rows']))
    direct = [top.materialize(row, source_root, output_dir)
              for row in data['rows']]
    composed = [top.materialize_extension(row, direct, output_dir)
                for row in data['extensions']]
    return direct + composed


def screen(digest, parents, seeds=None):
    public = top.comparison(digest)
    if seeds is None:
        seeds = top.initial_seeds()
        for row in parents:
            key = tuple(row['shape'])
            seeds[key] = min(seeds.get(key, row['rank']), row['rank'])
    baseline = top.solver(seeds)
    best = {}
    projections = 0
    for parent in parents:
        source = Path(parent['output'])
        shape, terms = top.read_blob(source.read_bytes())
        if (hashlib.sha256(source.read_bytes()).hexdigest() != parent['sha256'] or
                len(terms) != parent['rank'] or
                tuple(sorted(shape)) != tuple(parent['shape'])):
            raise ValueError('parent tensor mismatch')
        top.exact(shape, terms)
        for axis, extent in enumerate(shape):
            for coordinate in range(extent):
                projections += 1
                target, raw = top.project(shape, terms, axis, coordinate)
                key = tuple(sorted(target))
                if key not in public:
                    continue
                width = max(target[0] * target[1], target[1] * target[2],
                            target[0] * target[2])
                result, history = top.compress_shared(raw, max_bits=width)
                rank = len(result)
                limit = min(public[key], baseline(key))
                if rank >= limit:
                    continue
                output_sha256 = hashlib.sha256(top.blob(target, result)).hexdigest()
                row = dict(shape=list(key), rank=rank, raw_rank=len(raw),
                           cleanup_steps=len(history), public_rank=public[key],
                           local_baseline_rank=baseline(key),
                           source_shape=list(shape), source_rank=len(terms),
                           source_sha256=parent['sha256'], axis=axis,
                           deleted_coordinate=coordinate, sha256=output_sha256)
                choice = (rank, output_sha256)
                if key not in best or choice < best[key][0]:
                    best[key] = choice, row
    return dict(schema=1, field='GF(2)', record_claim=False,
                source_parent_count=len(parents), projections=projections,
                rows=sorted((row for _, row in best.values()),
                            key=lambda row: row['shape']))


def screen_recursive(digest, parents, scratch_root, max_depth):
    if not 1 <= max_depth <= 8:
        raise ValueError('depth must be between 1 and 8')
    seeds = top.initial_seeds()
    for row in parents:
        key = tuple(row['shape'])
        seeds[key] = min(seeds.get(key, row['rank']), row['rank'])
    all_parents = list(parents)
    generation = list(parents)
    rows = []
    projections = 0
    for depth in range(1, max_depth + 1):
        if not generation:
            break
        result = screen(digest, generation, seeds)
        projections += result['projections']
        generation = []
        for row in result['rows']:
            row = dict(row, depth=depth)
            verified = materialize_child(row, all_parents,
                                         scratch_root / f'depth{depth}')
            generation.append(verified)
            all_parents.append(verified)
            rows.append(row)
            key = tuple(row['shape'])
            seeds[key] = min(seeds.get(key, row['rank']), row['rank'])
    return dict(schema=1, field='GF(2)', record_claim=False,
                source_parent_count=len(parents), max_depth=max_depth,
                projections=projections, rows=rows)


def materialize_child(row, parents, output_dir):
    matches = [parent for parent in parents
               if parent['sha256'] == row['source_sha256']]
    if len(matches) != 1:
        raise ValueError('missing or ambiguous parent')
    raw_source = Path(matches[0]['output']).read_bytes()
    if hashlib.sha256(raw_source).hexdigest() != row['source_sha256']:
        raise ValueError('parent digest mismatch')
    shape, terms = top.read_blob(raw_source)
    if list(shape) != row['source_shape'] or len(terms) != row['source_rank']:
        raise ValueError('parent shape/rank mismatch')
    top.exact(shape, terms)
    axis, coordinate = row['axis'], row['deleted_coordinate']
    target, raw = top.project(shape, terms, axis, coordinate)
    keep = [list(range(n)) for n in shape]
    keep[axis].pop(coordinate)
    if raw != project_grid(shape, terms, keep):
        raise ValueError('independent projection mismatch')
    width = max(target[0] * target[1], target[1] * target[2],
                target[0] * target[2])
    result, history = top.compress_shared(raw, max_bits=width)
    if (tuple(sorted(target)) != tuple(row['shape']) or
            len(raw) != row['raw_rank'] or len(result) != row['rank'] or
            len(history) != row['cleanup_steps']):
        raise ValueError('child rank/cleanup mismatch')
    top.exact(target, result)
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / ('x'.join(map(str, target)) + f'-r{len(result)}.mfw')
    if output.exists():
        raise FileExistsError(output)
    output.write_bytes(top.blob(target, result))
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    if digest != row['sha256']:
        raise ValueError('child digest mismatch')
    checked = json.loads(subprocess.check_output(
        ['ruby', str(HERE / 'verify_tensor.rb'), '--shape',
         'x'.join(map(str, target)), str(output)], text=True))[0]
    if not checked['exact'] or checked['rank'] != len(result) or checked['sha256'] != digest:
        raise ValueError('independent full tensor verification failed')
    return dict(row, output=str(output))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--digest', type=Path)
    group.add_argument('--replay-manifest', type=Path)
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--depth', type=int, default=1)
    args = parser.parse_args()
    if args.replay_manifest and args.output_dir is None:
        parser.error('--replay-manifest requires --output-dir')
    with tempfile.TemporaryDirectory(prefix='metaflip-composed-child-') as tmp:
        root = Path(tmp)
        parents = build_parents(root / 'sources', root / 'parents')
        data = (json.loads(args.replay_manifest.read_text()) if args.replay_manifest
                else screen_recursive(json.loads(args.digest.read_text()), parents,
                                      root / 'children', args.depth))
        if args.output_dir:
            args.output_dir.mkdir(parents=True, exist_ok=False)
            rows = []
            for row in data['rows']:
                verified = materialize_child(row, parents, args.output_dir)
                parents.append(verified)
                rows.append(verified)
        else:
            rows = data['rows']
        print(json.dumps(dict(data, rows=rows), indent=2))


if __name__ == '__main__':
    main()
