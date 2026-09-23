#!/usr/bin/env python3
"""Screen exact two-pass basis rewrites and their coordinate projections."""
import argparse
import hashlib
from itertools import permutations
import json
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
import screen_neutral_basis_children as neutral
import screen_top_two_projection_children as top
from verify_cofactor_mergers import refactor_shared

HERE = Path(__file__).resolve().parent
ONE_PASS = HERE / 'certificates/structured-neutral-children-20260923/manifest.json'
PARENT = HERE / 'certificates/structured-parent-projections-20260923/manifest.json'
COMPOSED = HERE / 'certificates/neutral-basis-children-20260923/manifest.json'
CHAIN = HERE / 'certificates/composed-parent-children-20260923/manifest.json'
COMPOSED_TWO = HERE / 'certificates/two-pass-composed-children-20260923/manifest.json'
FIRST = HERE / 'certificates/two-pass-basis-children-20260923/manifest.json'
SECOND = HERE / 'certificates/two-pass-basis-descendants-20260923/manifest.json'


def baseline_seeds(parent_set='structured-projections'):
    seeds = top.initial_seeds()
    paths = [PARENT, COMPOSED, ONE_PASS]
    if parent_set in ('composed-chain', 'composed-descendants'):
        paths.extend((CHAIN, FIRST, SECOND))
    if parent_set == 'composed-descendants':
        paths.append(COMPOSED_TWO)
    if parent_set in ('first-generation', 'second-generation'):
        paths.append(FIRST)
    if parent_set == 'second-generation':
        paths.append(SECOND)
    for path in paths:
        data = json.loads(path.read_text())
        for row in data['rows'] + data.get('extensions', []) + data.get('descendants', []):
            key = tuple(row['shape'])
            seeds[key] = min(seeds.get(key, row['rank']), row['rank'])
    return seeds


def two_pass(terms, shape, mode):
    if not 6 <= mode < 18:
        raise ValueError('two-pass mode outside 6..17')
    width = max(shape[0] * shape[1], shape[1] * shape[2], shape[0] * shape[2])
    order = tuple(permutations(range(3)))[(mode - 6) // 2]
    current = terms
    for _ in range(2):
        for axis in order:
            current, _ = refactor_shared(current, axis, max_bits=width,
                                         reverse_columns=bool(mode % 2))
        if current == terms:
            break
    result, _ = top.compress_shared(current, max_bits=width)
    return result


def source_row(parent):
    raw = Path(parent['output']).read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if digest != parent['sha256']:
        raise ValueError('parent digest mismatch')
    shape, terms = top.read_blob(raw)
    if tuple(sorted(shape)) != tuple(parent['shape']) or len(terms) != parent['rank']:
        raise ValueError('parent shape/rank mismatch')
    top.exact(shape, terms)
    return shape, terms, digest


def screen(parents, digest, parent_set='structured-projections'):
    public = top.comparison(digest)
    baseline = top.solver(baseline_seeds(parent_set))
    best = {}
    counts = dict(parents=len(parents), modes=0, projections=0)
    for parent in parents:
        shape, terms, source_hash = source_row(parent)
        for mode in range(6, 18):
            basis = two_pass(terms, shape, mode)
            top.exact(shape, basis)
            basis_hash = hashlib.sha256(top.blob(shape, basis)).hexdigest()
            counts['modes'] += 1
            common = dict(source_shape=list(shape), source_rank=len(terms),
                          source_sha256=source_hash, mode=mode,
                          basis_rank=len(basis), basis_sha256=basis_hash)

            def retain(target, result, details):
                key = tuple(sorted(target))
                if len(result) >= min(public.get(key, 10**18), baseline(key)):
                    return
                raw = top.blob(target, result)
                candidate = dict(shape=list(key), oriented_shape=list(target),
                                 rank=len(result),
                                 local_baseline_rank=baseline(key),
                                 public_rank=public.get(key),
                                 sha256=hashlib.sha256(raw).hexdigest(),
                                 **common, **details)
                if key not in best or (candidate['rank'], candidate['sha256']) < (
                        best[key]['rank'], best[key]['sha256']):
                    top.exact(target, result)
                    best[key] = candidate

            retain(shape, basis, dict(kind='basis'))
            for axis, extent in enumerate(shape):
                for coordinate in range(extent):
                    counts['projections'] += 1
                    target, raw_child = top.project(shape, basis, axis, coordinate)
                    width = max(target[0] * target[1], target[1] * target[2],
                                target[0] * target[2])
                    child, history = top.compress_shared(raw_child, max_bits=width)
                    retain(target, child, dict(kind='projection', axis=axis,
                                               deleted_coordinate=coordinate,
                                               raw_rank=len(raw_child),
                                               cleanup_steps=len(history)))
    return dict(schema=1, field='GF(2)', record_claim=False,
                parent_set=parent_set, counts=counts,
                rows=sorted(best.values(), key=lambda row: row['shape']))


def materialize(row, parents, output_dir):
    matches = [p for p in parents if p['sha256'] == row['source_sha256']]
    if len(matches) != 1:
        raise ValueError('missing or ambiguous source')
    shape, terms, _ = source_row(matches[0])
    if list(shape) != row['source_shape'] or len(terms) != row['source_rank']:
        raise ValueError('source fields mismatch')
    basis = two_pass(terms, shape, row['mode'])
    expected_basis_rank = row.get('basis_rank', row['rank'] if row['kind'] == 'basis' else None)
    if len(basis) != expected_basis_rank or hashlib.sha256(
            top.blob(shape, basis)).hexdigest() != row['basis_sha256']:
        raise ValueError('basis mismatch')
    top.exact(shape, basis)
    if row['kind'] == 'basis':
        target, result = shape, basis
    elif row['kind'] == 'projection':
        axis, coordinate = row['axis'], row['deleted_coordinate']
        target, raw_child = top.project(shape, basis, axis, coordinate)
        keep = [list(range(n)) for n in shape]
        keep[axis].pop(coordinate)
        if raw_child != neutral.project_grid(shape, basis, keep):
            raise ValueError('independent projection mismatch')
        width = max(target[0] * target[1], target[1] * target[2],
                    target[0] * target[2])
        result, history = top.compress_shared(raw_child, max_bits=width)
        if len(raw_child) != row['raw_rank'] or len(history) != row['cleanup_steps']:
            raise ValueError('cleanup metadata mismatch')
    else:
        raise ValueError('unknown result kind')
    raw = top.blob(target, result)
    if (list(target) != row['oriented_shape'] or
            tuple(sorted(target)) != tuple(row['shape']) or
            len(result) != row['rank'] or
            hashlib.sha256(raw).hexdigest() != row['sha256']):
        raise ValueError('result mismatch')
    top.exact(target, result)
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / ('x'.join(map(str, target)) +
                         f'-r{len(result)}-{row["sha256"][:12]}.mfw')
    if path.exists():
        raise FileExistsError(path)
    path.write_bytes(raw)
    checked = json.loads(subprocess.check_output(
        ['ruby', str(HERE / 'verify_tensor.rb'), '--shape',
         'x'.join(map(str, target)), str(path)], text=True))[0]
    if not checked['exact'] or checked['rank'] != len(result) or checked['sha256'] != row['sha256']:
        raise ValueError('independent full-tensor verification failed')
    return dict(row, output=str(path))


def build_parents(root, parent_set):
    if parent_set == 'composed-descendants':
        parents = build_parents(root / 'sources', 'composed-chain')
        return [materialize(row, parents, root / 'first')
                for row in json.loads(COMPOSED_TWO.read_text())['rows']]
    if parent_set == 'composed-chain':
        parents = neutral.build_parents(root / 'composed')
        for row in json.loads(COMPOSED.read_text())['rows']:
            parents.append(neutral.materialize(row, parents, root / 'neutral'))
        return parents
    parents = neutral.build_structured_parents(root / 'structured')
    if parent_set == 'structured-projections':
        return parents
    first = json.loads(FIRST.read_text())
    parents = [materialize(row, parents, root / 'first') for row in first['rows']]
    if parent_set == 'first-generation':
        return parents
    second = json.loads(SECOND.read_text())
    return [materialize(row, parents, root / 'second') for row in second['rows']]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--digest', type=Path)
    group.add_argument('--replay-manifest', type=Path)
    parser.add_argument('--parent-set', choices=('structured-projections',
                                                  'first-generation',
                                                  'second-generation',
                                                  'composed-chain',
                                                  'composed-descendants'))
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--manifest-path', type=Path)
    args = parser.parse_args()
    if args.replay_manifest and args.output_dir is None:
        parser.error('--replay-manifest requires --output-dir')
    if args.replay_manifest and args.manifest_path:
        parser.error('--manifest-path requires --digest')
    replay = json.loads(args.replay_manifest.read_text()) if args.replay_manifest else None
    parent_set = args.parent_set or (replay or {}).get('parent_set', 'structured-projections')
    if replay and parent_set != replay['parent_set']:
        parser.error('parent set conflicts with replay manifest')
    with tempfile.TemporaryDirectory(prefix='metaflip-two-pass-children-') as temp:
        parents = build_parents(Path(temp) / 'parents', parent_set)
        data = replay if replay else screen(parents, json.loads(args.digest.read_text()),
                                           parent_set)
        manifest_data = data
        if args.output_dir:
            args.output_dir.mkdir(exist_ok=False)
            data = dict(data, rows=[materialize(row, parents, args.output_dir)
                                    for row in data['rows']])
        if args.manifest_path:
            args.manifest_path.parent.mkdir(parents=True, exist_ok=True)
            args.manifest_path.write_text(json.dumps(manifest_data, indent=2) + '\n')
        print(json.dumps(data, indent=2))


if __name__ == '__main__':
    main()
