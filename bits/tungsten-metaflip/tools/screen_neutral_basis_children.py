#!/usr/bin/env python3
"""Screen neutral GF(2) matrix-basis rewrites before coordinate deletion.

Sources are the exact composed-parent projection chain. A same-rank basis
variant is useful only if its projected child beats the current closure.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import screen_composed_parent_children as chain
import screen_top_two_projection_children as top
from screen_structured_parent_projections import project_grid
from verify_cofactor_mergers import refactor_shared

HERE = Path(__file__).resolve().parent
PARENT_MANIFEST = HERE / 'certificates/composed-parent-children-20260923/manifest.json'


def build_parents(root):
    parents = chain.build_parents(root / 'sources', root / 'initial')
    children = []
    for row in json.loads(PARENT_MANIFEST.read_text())['rows']:
        verified = chain.materialize_child(row, parents, root / 'children')
        parents.append(verified)
        children.append(verified)
    return children


def initial_seeds(parents):
    seeds = top.initial_seeds()
    for path in (top.KNOWN_MANIFEST, PARENT_MANIFEST):
        data = json.loads(path.read_text())
        for row in data['rows'] + data.get('extensions', []):
            key = tuple(row['shape'])
            seeds[key] = min(seeds.get(key, row['rank']), row['rank'])
    for row in parents:
        key = tuple(row['shape'])
        seeds[key] = min(seeds.get(key, row['rank']), row['rank'])
    return seeds


def screen_generation(digest, parents, seeds):
    public = top.comparison(digest)
    baseline = top.solver(seeds)
    best = {}
    variants = projections = 0
    for parent in parents:
        raw = Path(parent['output']).read_bytes()
        if hashlib.sha256(raw).hexdigest() != parent['sha256']:
            raise ValueError('source digest mismatch')
        shape, terms = top.read_blob(raw)
        if len(terms) != parent['rank'] or tuple(sorted(shape)) != tuple(parent['shape']):
            raise ValueError('source shape/rank mismatch')
        top.exact(shape, terms)
        width = max(shape[0] * shape[1], shape[1] * shape[2], shape[0] * shape[2])
        for fixed_axis in range(3):
            for reverse in (False, True):
                basis, changed = refactor_shared(terms, fixed_axis, max_bits=width,
                                                 reverse_columns=reverse)
                if basis == terms:
                    continue
                variants += 1
                top.exact(shape, basis)
                basis_sha256 = hashlib.sha256(top.blob(shape, basis)).hexdigest()
                for axis, extent in enumerate(shape):
                    for coordinate in range(extent):
                        projections += 1
                        target, raw_child = top.project(shape, basis, axis, coordinate)
                        key = tuple(sorted(target))
                        if key not in public:
                            continue
                        target_width = max(target[0] * target[1],
                                           target[1] * target[2], target[0] * target[2])
                        result, history = top.compress_shared(raw_child,
                                                              max_bits=target_width)
                        rank = len(result)
                        if rank >= min(public[key], baseline(key)):
                            continue
                        sha256 = hashlib.sha256(top.blob(target, result)).hexdigest()
                        row = dict(shape=list(key), rank=rank, raw_rank=len(raw_child),
                                   cleanup_steps=len(history), public_rank=public[key],
                                   local_baseline_rank=baseline(key),
                                   source_shape=list(shape), source_rank=len(terms),
                                   source_sha256=parent['sha256'], fixed_axis=fixed_axis,
                                   reverse=reverse, basis_rank=len(basis),
                                   basis_changed_groups=len(changed),
                                   basis_sha256=basis_sha256, axis=axis,
                                   deleted_coordinate=coordinate, sha256=sha256)
                        choice = (rank, sha256)
                        if key not in best or choice < best[key][0]:
                            best[key] = choice, row
    return dict(basis_variants=variants, projections=projections,
                rows=sorted((row for _, row in best.values()),
                            key=lambda row: row['shape']))


def materialize(row, parents, output_dir):
    matches = [parent for parent in parents
               if parent['sha256'] == row['source_sha256']]
    if len(matches) != 1:
        raise ValueError('missing or ambiguous source')
    raw = Path(matches[0]['output']).read_bytes()
    if hashlib.sha256(raw).hexdigest() != row['source_sha256']:
        raise ValueError('source digest mismatch')
    shape, terms = top.read_blob(raw)
    if list(shape) != row['source_shape'] or len(terms) != row['source_rank']:
        raise ValueError('source shape/rank mismatch')
    top.exact(shape, terms)
    width = max(shape[0] * shape[1], shape[1] * shape[2], shape[0] * shape[2])
    basis, changed = refactor_shared(terms, row['fixed_axis'], max_bits=width,
                                     reverse_columns=row['reverse'])
    if (len(basis) != row['basis_rank'] or
            len(changed) != row['basis_changed_groups'] or
            hashlib.sha256(top.blob(shape, basis)).hexdigest() != row['basis_sha256']):
        raise ValueError('neutral basis mismatch')
    top.exact(shape, basis)
    axis, coordinate = row['axis'], row['deleted_coordinate']
    target, raw_child = top.project(shape, basis, axis, coordinate)
    keep = [list(range(n)) for n in shape]
    keep[axis].pop(coordinate)
    if raw_child != project_grid(shape, basis, keep):
        raise ValueError('independent projection mismatch')
    target_width = max(target[0] * target[1], target[1] * target[2],
                       target[0] * target[2])
    result, history = top.compress_shared(raw_child, max_bits=target_width)
    if (tuple(sorted(target)) != tuple(row['shape']) or
            len(raw_child) != row['raw_rank'] or len(result) != row['rank'] or
            len(history) != row['cleanup_steps']):
        raise ValueError('projected child mismatch')
    top.exact(target, result)
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / ('x'.join(map(str, target)) +
                           f'-r{len(result)}-{row["sha256"][:12]}.mfw')
    if output.exists():
        raise FileExistsError(output)
    output.write_bytes(top.blob(target, result))
    sha256 = hashlib.sha256(output.read_bytes()).hexdigest()
    if sha256 != row['sha256']:
        raise ValueError('child digest mismatch')
    checked = json.loads(subprocess.check_output(
        ['ruby', str(HERE / 'verify_tensor.rb'), '--shape',
         'x'.join(map(str, target)), str(output)], text=True))[0]
    if not checked['exact'] or checked['rank'] != len(result) or checked['sha256'] != sha256:
        raise ValueError('independent full tensor verification failed')
    return dict(row, output=str(output))


def screen_recursive(digest, parents, scratch_root, max_depth):
    if not 1 <= max_depth <= 5:
        raise ValueError('depth must be between 1 and 5')
    seeds = initial_seeds(parents)
    all_parents = list(parents)
    generation = list(parents)
    rows = []
    variants = projections = 0
    for depth in range(1, max_depth + 1):
        if not generation:
            break
        result = screen_generation(digest, generation, seeds)
        variants += result['basis_variants']
        projections += result['projections']
        generation = []
        for row in result['rows']:
            row = dict(row, depth=depth)
            verified = materialize(row, all_parents, scratch_root / f'depth{depth}')
            generation.append(verified)
            all_parents.append(verified)
            rows.append(row)
            key = tuple(row['shape'])
            seeds[key] = min(seeds.get(key, row['rank']), row['rank'])
    return dict(schema=1, field='GF(2)', record_claim=False,
                initial_parent_count=len(parents), max_depth=max_depth,
                basis_variants=variants, projections=projections, rows=rows)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--digest', type=Path)
    group.add_argument('--replay-manifest', type=Path)
    parser.add_argument('--depth', type=int, default=1)
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    if args.replay_manifest and args.output_dir is None:
        parser.error('--replay-manifest requires --output-dir')
    with tempfile.TemporaryDirectory(prefix='metaflip-neutral-basis-child-') as tmp:
        root = Path(tmp)
        parents = build_parents(root / 'parents')
        data = (json.loads(args.replay_manifest.read_text()) if args.replay_manifest
                else screen_recursive(json.loads(args.digest.read_text()), parents,
                                      root / 'search', args.depth))
        if args.output_dir:
            args.output_dir.mkdir(parents=True, exist_ok=False)
            rows = []
            for row in data['rows']:
                verified = materialize(row, parents, args.output_dir)
                parents.append(verified)
                rows.append(verified)
        else:
            rows = data['rows']
        print(json.dumps(dict(data, rows=rows), indent=2))


if __name__ == '__main__':
    main()
