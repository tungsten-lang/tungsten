#!/usr/bin/env python3
"""Screen near-best intermediate GF(2) projections for better grandchildren.

Lille ranks are numerical comparison data, not tensor witnesses or a
world-record oracle. Only exact structured-parent schemes supply inputs.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from screen_structured_parent_projections import (
    HERE, MANIFEST, blob, compress_shared, exact, load_source, local_seeds,
    project, project_grid, replay_sources, solver,
)

PARENT_MANIFEST = HERE / 'certificates/structured-parent-projections-20260923/manifest.json'
RANK_SLACK = 25


def comparison(digest):
    public = {}
    for entry in digest['entries']:
        key, rank = tuple(sorted(entry['format'])), entry['rank']
        if key in public and public[key] != rank:
            raise ValueError(f'conflicting public rank for {key}')
        public[key] = rank
    return public


def target_rows():
    return json.loads(PARENT_MANIFEST.read_text())


def relevant_sources():
    targets = {tuple(row['shape']) for row in target_rows()['rows']}
    return [entry for entry in json.loads(MANIFEST.read_text())['rows']
            if any(tuple(sorted(entry['result_shape'][:dim] +
                                [entry['result_shape'][dim] - 1] +
                                entry['result_shape'][dim + 1:])) in targets
                   for dim in range(3) if entry['result_shape'][dim] > 1)]


def screen(digest, source_root):
    parent = target_rows()
    targets = {tuple(row['shape']): row['rank'] for row in parent['rows']}
    seeds = local_seeds()
    for row in parent['rows'] + parent['extensions'] + parent['descendants']:
        key = tuple(row['shape'])
        seeds[key] = min(seeds.get(key, row['rank']), row['rank'])
    baseline = solver(dict(seeds))
    public = comparison(digest)
    best = {}
    intermediate_count = child_count = 0
    for entry in relevant_sources():
        pin = dict(source_portfolio_shape=entry['shape'],
                   source_shape=entry['result_shape'],
                   source_scheme_sha256=entry['result_sha256'])
        shape, terms = load_source(pin, source_root)
        for dimension, extent in enumerate(shape):
            if extent <= 1:
                continue
            middle_key = tuple(sorted(shape[:dimension] + (extent - 1,) +
                                      shape[dimension + 1:]))
            if middle_key not in targets:
                continue
            for coordinate in range(extent):
                middle, projected = project(shape, terms, dimension, coordinate)
                width = max(middle[0] * middle[1], middle[1] * middle[2],
                            middle[0] * middle[2])
                cleaned, history = compress_shared(projected, max_bits=width)
                if not targets[middle_key] < len(cleaned) <= targets[middle_key] + RANK_SLACK:
                    continue
                intermediate_count += 1
                middle_sha256 = hashlib.sha256(blob(middle, cleaned)).hexdigest()
                for second_dimension, second_extent in enumerate(middle):
                    if second_extent <= 1:
                        continue
                    child_key = tuple(sorted(middle[:second_dimension] +
                                             (second_extent - 1,) +
                                             middle[second_dimension + 1:]))
                    if child_key not in public:
                        child_count += second_extent
                        continue
                    for second_coordinate in range(second_extent):
                        child_count += 1
                        target, raw = project(middle, cleaned, second_dimension,
                                              second_coordinate)
                        key = tuple(sorted(target))
                        if key != child_key:
                            raise ValueError('projection shape mismatch')
                        width = max(target[0] * target[1], target[1] * target[2],
                                    target[0] * target[2])
                        result, second_history = compress_shared(raw, max_bits=width)
                        rank = len(result)
                        if rank >= min(public[key], baseline(key)):
                            continue
                        output_sha256 = hashlib.sha256(blob(target, result)).hexdigest()
                        row = dict(shape=list(key), rank=rank, raw_rank=len(raw),
                                   cleanup_steps=len(second_history), public_rank=public[key],
                                   local_baseline_rank=baseline(key), **pin,
                                   first_dimension=dimension,
                                   first_deleted_coordinate=coordinate,
                                   middle_shape=list(middle), middle_raw_rank=len(projected),
                                   middle_rank=len(cleaned),
                                   middle_cleanup_steps=len(history),
                                   middle_sha256=middle_sha256,
                                   second_dimension=second_dimension,
                                   second_deleted_coordinate=second_coordinate,
                                   sha256=output_sha256)
                        choice = (rank, output_sha256)
                        if key not in best or choice < best[key][0]:
                            best[key] = choice, row
    return dict(schema=1, field='GF(2)', record_claim=False,
                first_rank_slack=RANK_SLACK, intermediate_count=intermediate_count,
                child_projections=child_count,
                rows=sorted((row for _, row in best.values()), key=lambda row: row['shape']))


def materialize(row, source_root, output_dir):
    shape, terms = load_source(row, source_root)
    dimension, coordinate = row['first_dimension'], row['first_deleted_coordinate']
    middle, raw = project(shape, terms, dimension, coordinate)
    keep = [list(range(n)) for n in shape]
    keep[dimension].pop(coordinate)
    if raw != project_grid(shape, terms, keep):
        raise ValueError('first independent projection mismatch')
    width = max(middle[0] * middle[1], middle[1] * middle[2], middle[0] * middle[2])
    cleaned, history = compress_shared(raw, max_bits=width)
    if (list(middle) != row['middle_shape'] or len(raw) != row['middle_raw_rank'] or
            len(cleaned) != row['middle_rank'] or
            len(history) != row['middle_cleanup_steps'] or
            hashlib.sha256(blob(middle, cleaned)).hexdigest() != row['middle_sha256']):
        raise ValueError('intermediate projection mismatch')
    exact(middle, cleaned)

    dimension, coordinate = row['second_dimension'], row['second_deleted_coordinate']
    target, raw = project(middle, cleaned, dimension, coordinate)
    keep = [list(range(n)) for n in middle]
    keep[dimension].pop(coordinate)
    if raw != project_grid(middle, cleaned, keep):
        raise ValueError('second independent projection mismatch')
    width = max(target[0] * target[1], target[1] * target[2], target[0] * target[2])
    result, history = compress_shared(raw, max_bits=width)
    if (tuple(sorted(target)) != tuple(row['shape']) or len(raw) != row['raw_rank'] or
            len(result) != row['rank'] or len(history) != row['cleanup_steps']):
        raise ValueError('final projection mismatch')
    exact(target, result)
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / ('x'.join(map(str, target)) + f'-r{len(result)}.mfw')
    if output.exists():
        raise FileExistsError(output)
    output.write_bytes(blob(target, result))
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    if digest != row['sha256']:
        raise ValueError('final tensor digest mismatch')
    checked = json.loads(subprocess.check_output(
        ['ruby', str(HERE / 'verify_tensor.rb'), '--shape',
         'x'.join(map(str, target)), str(output)], text=True))[0]
    if not checked['exact'] or checked['rank'] != len(result) or checked['sha256'] != digest:
        raise ValueError('independent tensor verification failed')
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
    with tempfile.TemporaryDirectory(prefix='metaflip-diverse-projection-') as tmp:
        source_root = Path(tmp) / 'sources'
        if args.replay_manifest:
            data = json.loads(args.replay_manifest.read_text())
            entries = data['rows']
            replay_sources(source_root, (row['source_portfolio_shape'] for row in entries))
        else:
            replay_sources(source_root, (entry['shape'] for entry in relevant_sources()))
            data = screen(json.loads(args.digest.read_text()), source_root)
            entries = data['rows']
        if args.output_dir:
            args.output_dir.mkdir(parents=True, exist_ok=False)
            entries = [materialize(row, source_root, args.output_dir) for row in entries]
        print(json.dumps(dict(data, rows=entries), indent=2))


if __name__ == '__main__':
    main()
