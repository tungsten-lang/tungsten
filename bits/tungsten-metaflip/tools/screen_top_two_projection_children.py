#!/usr/bin/env python3
"""Screen a bounded top-two representation beam over exact GF(2) parents.

The external Lille ranks are comparison numbers, not tensor witnesses or a
world-record oracle. Every retained construction is independently replayed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path[:0] = [str(HERE), str(ROOT / 'benchmarks/matmul/metaflip')]
from screen_diverse_projection_children import comparison, materialize  # noqa: E402
from screen_structured_parent_projections import (  # noqa: E402
    MANIFEST, blob, compress_shared, exact, load_source, local_seeds,
    project, read_blob, replay_sources, solver,
)
from verify_cofactor_mergers import orient  # noqa: E402
from verify_composition_targets import kronecker  # noqa: E402
from verify_representation_portfolio import parse_terms  # noqa: E402

CERTIFICATES = HERE / 'certificates'
PARENT_MANIFEST = CERTIFICATES / 'structured-parent-projections-20260923/manifest.json'
NEAR_MANIFEST = CERTIFICATES / 'diverse-projection-children-20260923/manifest.json'
KNOWN_MANIFEST = CERTIFICATES / 'top-two-projection-children-20260923/manifest.json'
PER_SHAPE = 2
RANK_SLACK = 50


def initial_seeds():
    seeds = local_seeds()
    for path in (PARENT_MANIFEST, NEAR_MANIFEST):
        data = json.loads(path.read_text())
        for row in data['rows'] + data.get('extensions', []) + data.get('descendants', []):
            key = tuple(row['shape'])
            seeds[key] = min(seeds.get(key, row['rank']), row['rank'])
    return seeds


def screen(digest, source_root):
    public = comparison(digest)
    baseline = solver(initial_seeds())
    top = {}
    source_cache = {}
    projections = 0
    for entry in json.loads(MANIFEST.read_text())['rows']:
        pin = dict(source_portfolio_shape=entry['shape'],
                   source_shape=entry['result_shape'],
                   source_scheme_sha256=entry['result_sha256'])
        shape, terms = load_source(pin, source_root)
        source_cache[tuple(entry['shape'])] = shape, terms
        for dimension, extent in enumerate(shape):
            for coordinate in range(extent):
                projections += 1
                target, raw = project(shape, terms, dimension, coordinate)
                key = tuple(sorted(target))
                width = max(target[0] * target[1], target[1] * target[2],
                            target[0] * target[2])
                cleaned, _ = compress_shared(raw, max_bits=width)
                candidate = dict(shape=list(key), rank=len(cleaned),
                                 sha256=hashlib.sha256(blob(target, cleaned)).hexdigest(),
                                 dimension=dimension, deleted_coordinate=coordinate,
                                 **pin)
                bucket = top.setdefault(key, [])
                if candidate['sha256'] not in {row['sha256'] for row in bucket}:
                    bucket.append(candidate)
                    bucket.sort(key=lambda row: (row['rank'], row['sha256']))
                    del bucket[PER_SHAPE:]

    best = {}
    selected = children = 0
    for key, bucket in sorted(top.items()):
        threshold = min(public.get(key, 10**18), baseline(key))
        if bucket[0]['rank'] > threshold + RANK_SLACK:
            continue
        for first in bucket:
            if first['rank'] > threshold + RANK_SLACK:
                continue
            shape, terms = source_cache[tuple(first['source_portfolio_shape'])]
            middle, raw = project(shape, terms, first['dimension'],
                                  first['deleted_coordinate'])
            width = max(middle[0] * middle[1], middle[1] * middle[2],
                        middle[0] * middle[2])
            cleaned, history = compress_shared(raw, max_bits=width)
            middle_sha256 = hashlib.sha256(blob(middle, cleaned)).hexdigest()
            if len(cleaned) != first['rank'] or middle_sha256 != first['sha256']:
                raise ValueError('top-two first projection mismatch')
            selected += 1
            for second_dimension, extent in enumerate(middle):
                if extent <= 1:
                    continue
                child_key = tuple(sorted(middle[:second_dimension] + (extent - 1,) +
                                         middle[second_dimension + 1:]))
                children += extent
                if child_key not in public:
                    continue
                for second_coordinate in range(extent):
                    target, raw_child = project(middle, cleaned, second_dimension,
                                                second_coordinate)
                    width = max(target[0] * target[1], target[1] * target[2],
                                target[0] * target[2])
                    result, second_history = compress_shared(raw_child, max_bits=width)
                    rank = len(result)
                    if rank >= min(public[child_key], baseline(child_key)):
                        continue
                    output_sha256 = hashlib.sha256(blob(target, result)).hexdigest()
                    row = dict(shape=list(child_key), rank=rank, raw_rank=len(raw_child),
                               cleanup_steps=len(second_history),
                               public_rank=public[child_key],
                               local_baseline_rank=baseline(child_key),
                               source_portfolio_shape=first['source_portfolio_shape'],
                               source_shape=first['source_shape'],
                               source_scheme_sha256=first['source_scheme_sha256'],
                               first_dimension=first['dimension'],
                               first_deleted_coordinate=first['deleted_coordinate'],
                               middle_shape=list(middle), middle_raw_rank=len(raw),
                               middle_rank=len(cleaned),
                               middle_cleanup_steps=len(history),
                               middle_sha256=middle_sha256,
                               second_dimension=second_dimension,
                               second_deleted_coordinate=second_coordinate,
                               sha256=output_sha256)
                    choice = (rank, output_sha256)
                    if child_key not in best or choice < best[child_key][0]:
                        best[child_key] = choice, row

    rows = sorted((row for _, row in best.values()), key=lambda row: row['shape'])
    known = json.loads(KNOWN_MANIFEST.read_text())['extensions']
    available = {row['sha256'] for row in rows}
    extensions = [row for row in known
                  if row['large_source_sha256'] in available and
                  row['rank'] < min(public.get(tuple(row['shape']), row['rank']),
                                    baseline(tuple(row['shape'])))]
    return dict(schema=1, field='GF(2)', record_claim=False,
                first_projections=projections, first_shapes=len(top),
                per_shape=PER_SHAPE, rank_slack=RANK_SLACK,
                selected_intermediates=selected, child_projections=children,
                rows=rows, extensions=extensions)


def materialize_extension(row, direct_rows, output_dir):
    matches = [entry for entry in direct_rows
               if entry['sha256'] == row['large_source_sha256']]
    if len(matches) != 1:
        raise ValueError('missing or ambiguous large source')
    large_raw = Path(matches[0]['output']).read_bytes()
    if hashlib.sha256(large_raw).hexdigest() != row['large_source_sha256']:
        raise ValueError('large source digest mismatch')
    large_shape, large_terms = read_blob(large_raw)
    if len(large_terms) != row['large_source_rank']:
        raise ValueError('large source rank mismatch')
    exact(large_shape, large_terms)
    left_shape = tuple(row['large_orientation'])
    left = orient(large_shape, large_terms, left_shape)

    small_path = (ROOT / row['small_source']).resolve()
    if not small_path.is_relative_to(ROOT) or not small_path.is_file():
        raise ValueError('invalid small source path')
    small_raw = small_path.read_bytes()
    if hashlib.sha256(small_raw).hexdigest() != row['small_source_sha256']:
        raise ValueError('small source digest mismatch')
    right_shape = tuple(row['small_shape'])
    right = parse_terms(small_raw, row['small_rank'])
    exact(right_shape, right)
    target = tuple(a * b for a, b in zip(left_shape, right_shape))
    if tuple(row['shape']) != target or row['rank'] != len(left) * len(right):
        raise ValueError('invalid product shape/rank')
    result = kronecker(left_shape, left, right_shape, right)
    exact(target, result)
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / ('x'.join(map(str, target)) + f'-r{len(result)}.mfw')
    if output.exists():
        raise FileExistsError(output)
    output.write_bytes(blob(target, result))
    output_sha256 = hashlib.sha256(output.read_bytes()).hexdigest()
    if output_sha256 != row['sha256']:
        raise ValueError('product digest mismatch')
    checked = json.loads(subprocess.check_output(
        ['ruby', str(HERE / 'verify_tensor.rb'), '--shape',
         'x'.join(map(str, target)), str(output)], text=True))[0]
    if not checked['exact'] or checked['rank'] != len(result) or checked['sha256'] != output_sha256:
        raise ValueError('independent product tensor verification failed')
    return dict(row, output=str(output))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--digest', type=Path)
    group.add_argument('--replay-manifest', type=Path)
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    if args.replay_manifest and args.output_dir is None:
        parser.error('--replay-manifest requires --output-dir')
    with tempfile.TemporaryDirectory(prefix='metaflip-top-two-projection-') as tmp:
        source_root = Path(tmp) / 'sources'
        if args.replay_manifest:
            data = json.loads(args.replay_manifest.read_text())
            replay_sources(source_root,
                           (row['source_portfolio_shape'] for row in data['rows']))
        else:
            replay_sources(source_root,
                           (entry['shape'] for entry in json.loads(MANIFEST.read_text())['rows']))
            data = screen(json.loads(args.digest.read_text()), source_root)
        if args.output_dir:
            args.output_dir.mkdir(parents=True, exist_ok=False)
            rows = [materialize(row, source_root, args.output_dir)
                    for row in data['rows']]
            extensions = [materialize_extension(row, rows, args.output_dir)
                          for row in data['extensions']]
        else:
            rows, extensions = data['rows'], data['extensions']
        print(json.dumps(dict(data, rows=rows, extensions=extensions), indent=2))


if __name__ == '__main__':
    main()
