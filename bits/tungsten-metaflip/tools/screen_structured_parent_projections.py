#!/usr/bin/env python3
"""Screen and replay exact one-coordinate GF(2) portfolio projections.

The Lille digest is numerical comparison data, never a tensor witness or a
world-record oracle. The finite screen deletes one coordinate in any axis of
each exactly replayed structured-parent tensor, then applies exact matrix
cleanup. The retained rows are independently checked before admission.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path[:0] = [str(HERE), str(ROOT / 'bits/tungsten-metaflip/spec'),
                str(ROOT / 'benchmarks/matmul/metaflip')]
from check_wide_rectangular_closure import CANDIDATES, MANIFEST
from packed_composition_parity_test import exact
from verify_cofactor_mergers import compress_shared, orient
from verify_composition_targets import block
from verify_coordinate_projections import project_grid
from verify_representation_portfolio import parse_terms
from verify_recursive_portfolio import solver
from wide_matrix_cleanup_parity_test import blob, read_blob

EDGES = ((0, 1), (1, 2), (0, 2))
CERTIFICATES = HERE / 'certificates'
KNOWN_PROJECTIONS = CERTIFICATES / 'structured-parent-projections-20260923/manifest.json'


def drop_matrix(word, rows, cols, dimension, coordinate):
    """Delete a row or column from a row-major GF(2) matrix word."""
    if dimension == 0:
        lower = word & ((1 << (coordinate * cols)) - 1)
        return lower | ((word >> ((coordinate + 1) * cols)) << (coordinate * cols))
    old_mask = (1 << cols) - 1
    lower_mask = (1 << coordinate) - 1
    result = 0
    for row in range(rows):
        chunk = (word >> (row * cols)) & old_mask
        smaller = (chunk & lower_mask) | ((chunk >> (coordinate + 1)) << coordinate)
        result |= smaller << (row * (cols - 1))
    return result


def project(shape, terms, dimension, coordinate):
    if not 0 <= dimension < 3 or not 0 <= coordinate < shape[dimension] or shape[dimension] <= 1:
        raise ValueError('invalid deleted coordinate')
    parity = Counter()
    for term in terms:
        output = []
        for word, (left, right) in zip(term, EDGES):
            if dimension == left:
                output.append(drop_matrix(word, shape[left], shape[right], 0, coordinate))
            elif dimension == right:
                output.append(drop_matrix(word, shape[left], shape[right], 1, coordinate))
            else:
                output.append(word)
        if all(output):
            parity[tuple(output)] += 1
    target = list(shape)
    target[dimension] -= 1
    return tuple(target), sorted(term for term, count in parity.items() if count % 2)


def source_entry(portfolio_shape):
    rows = json.loads(MANIFEST.read_text())['rows']
    matches = [row for row in rows if row['shape'] == list(portfolio_shape)]
    if len(matches) != 1:
        raise ValueError(f'unknown or duplicate portfolio shape: {portfolio_shape}')
    return matches[0]


def load_source(row, source_root):
    entry = source_entry(row['source_portfolio_shape'])
    if (row['source_shape'] != entry['result_shape'] or
            row['source_scheme_sha256'] != entry['result_sha256']):
        raise ValueError('portfolio source pin mismatch')
    name = 'x'.join(map(str, entry['result_shape']))
    key = 'x'.join(map(str, entry['shape']))
    path = source_root / key / (name + '.mfw')
    shape, terms = read_blob(path.read_bytes())
    if shape != tuple(entry['result_shape']) or len(terms) != entry['rank']:
        raise ValueError('replayed source shape/rank mismatch')
    scheme = str(len(terms)) + '\n' + ''.join(' '.join(map(str, term)) + '\n' for term in terms)
    if hashlib.sha256(scheme.encode('ascii')).hexdigest() != entry['result_sha256']:
        raise ValueError('replayed source scheme digest mismatch')
    exact(shape, terms)
    return shape, terms


def materialize(row, source_root, output_dir):
    shape, terms = load_source(row, source_root)
    dimension, coordinate = row['dimension'], row['deleted_coordinate']
    target, projected = project(shape, terms, dimension, coordinate)
    keep = [list(range(n)) for n in shape]
    keep[dimension].pop(coordinate)
    if projected != project_grid(shape, terms, keep):
        raise ValueError('independent bit-grid projection mismatch')
    if tuple(sorted(target)) != tuple(row['shape']) or len(projected) != row['raw_rank']:
        raise ValueError('projection target/rank mismatch')
    width = max(target[0] * target[1], target[1] * target[2], target[0] * target[2])
    cleaned, history = compress_shared(projected, max_bits=width)
    if len(cleaned) != row['rank'] or len(history) != row['cleanup_steps']:
        raise ValueError('matrix cleanup mismatch')
    exact(target, cleaned)
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / ('x'.join(map(str, target)) + f'-r{len(cleaned)}.mfw')
    if path.exists():
        raise FileExistsError(path)
    path.write_bytes(blob(target, cleaned))
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if 'sha256' in row and digest != row['sha256']:
        raise ValueError('output tensor digest mismatch')
    checked = json.loads(subprocess.check_output(
        ['ruby', str(HERE / 'verify_tensor.rb'), '--shape',
         'x'.join(map(str, target)), str(path)], text=True))[0]
    if not checked['exact'] or checked['rank'] != len(cleaned) or checked['sha256'] != digest:
        raise ValueError('independent tensor verification failed')
    return dict(row, sha256=digest, output=str(path))


def materialize_extension(row, projection_dir, output_dir):
    small_path = (ROOT / row['small_source']).resolve()
    if not small_path.is_relative_to(ROOT) or not small_path.is_file():
        raise ValueError('invalid small source path')
    raw = small_path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != row['small_source_sha256']:
        raise ValueError('small source digest mismatch')
    small_shape = tuple(row['small_shape'])
    small_terms = parse_terms(raw, row['small_rank'])
    exact(small_shape, small_terms)
    axis, count = row['repeat_axis'], row['repeat_count']
    repeated_shape = list(small_shape)
    repeated_shape[axis] *= count
    repeated_shape = tuple(repeated_shape)
    repeated = []
    for k in range(count):
        offsets = [0, 0, 0]
        offsets[axis] = k * small_shape[axis]
        repeated.extend(block(small_shape, small_terms, repeated_shape, offsets))
    exact(repeated_shape, repeated)
    right_shape = tuple(row['repeat_orientation'])
    right = orient(repeated_shape, repeated, right_shape)

    large_shape = tuple(row['large_projection_shape'])
    filename = 'x'.join(map(str, large_shape)) + f'-r{row["large_projection_rank"]}.mfw'
    large_path = projection_dir / filename
    if hashlib.sha256(large_path.read_bytes()).hexdigest() != row['large_projection_sha256']:
        raise ValueError('large projection digest mismatch')
    actual_shape, large_terms = read_blob(large_path.read_bytes())
    if actual_shape != large_shape or len(large_terms) != row['large_projection_rank']:
        raise ValueError('large projection shape/rank mismatch')
    exact(large_shape, large_terms)
    left_shape = tuple(row['large_orientation'])
    left = orient(large_shape, large_terms, left_shape)
    target = tuple(row['target_orientation'])
    block_axis = row['block_axis']
    if (tuple(sorted(target)) != tuple(row['shape']) or
            any(left_shape[i] != right_shape[i] or target[i] != left_shape[i]
                for i in range(3) if i != block_axis) or
            target[block_axis] != left_shape[block_axis] + right_shape[block_axis]):
        raise ValueError('incompatible block shapes')
    offsets = [0, 0, 0]
    offsets[block_axis] = left_shape[block_axis]
    terms = block(left_shape, left, target, (0, 0, 0)) + \
        block(right_shape, right, target, offsets)
    width = max(target[0] * target[1], target[1] * target[2], target[0] * target[2])
    cleaned, history = compress_shared(terms, max_bits=width)
    if len(cleaned) != row['rank'] or len(history) != row['cleanup_steps']:
        raise ValueError('extension rank/cleanup mismatch')
    exact(target, cleaned)
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / ('x'.join(map(str, target)) + f'-r{len(cleaned)}.mfw')
    if output.exists():
        raise FileExistsError(output)
    output.write_bytes(blob(target, cleaned))
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    if digest != row['sha256']:
        raise ValueError('extension tensor digest mismatch')
    checked = json.loads(subprocess.check_output(
        ['ruby', str(HERE / 'verify_tensor.rb'), '--shape',
         'x'.join(map(str, target)), str(output)], text=True))[0]
    if not checked['exact'] or checked['rank'] != len(cleaned) or checked['sha256'] != digest:
        raise ValueError('independent extension tensor verification failed')
    return dict(row, output=str(output))


def materialize_descendant(row, parent_dir, output_dir):
    parent_shape = tuple(row['parent_shape'])
    filename = 'x'.join(map(str, parent_shape)) + f'-r{row["parent_rank"]}.mfw'
    parent_path = parent_dir / filename
    parent_raw = parent_path.read_bytes()
    if hashlib.sha256(parent_raw).hexdigest() != row['parent_sha256']:
        raise ValueError('descendant parent digest mismatch')
    shape, terms = read_blob(parent_raw)
    if shape != parent_shape or len(terms) != row['parent_rank']:
        raise ValueError('descendant parent shape/rank mismatch')
    exact(shape, terms)
    dimension, coordinate = row['dimension'], row['deleted_coordinate']
    target, projected = project(shape, terms, dimension, coordinate)
    keep = [list(range(n)) for n in shape]
    keep[dimension].pop(coordinate)
    if projected != project_grid(shape, terms, keep):
        raise ValueError('independent descendant projection mismatch')
    if tuple(sorted(target)) != tuple(row['shape']) or len(projected) != row['raw_rank']:
        raise ValueError('descendant shape/raw rank mismatch')
    width = max(target[0] * target[1], target[1] * target[2], target[0] * target[2])
    cleaned, history = compress_shared(projected, max_bits=width)
    if len(cleaned) != row['rank'] or len(history) != row['cleanup_steps']:
        raise ValueError('descendant cleanup mismatch')
    exact(target, cleaned)
    output_dir.mkdir(parents=True, exist_ok=True)
    output = output_dir / ('x'.join(map(str, target)) + f'-r{len(cleaned)}.mfw')
    if output.exists():
        raise FileExistsError(output)
    output.write_bytes(blob(target, cleaned))
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    if 'sha256' in row and digest != row['sha256']:
        raise ValueError('descendant tensor digest mismatch')
    checked = json.loads(subprocess.check_output(
        ['ruby', str(HERE / 'verify_tensor.rb'), '--shape',
         'x'.join(map(str, target)), str(output)], text=True))[0]
    if not checked['exact'] or checked['rank'] != len(cleaned) or checked['sha256'] != digest:
        raise ValueError('independent descendant tensor verification failed')
    return dict(row, sha256=digest, output=str(output))


def replay_sources(source_root, shapes):
    command = ['ruby', str(HERE / 'replay_structured_parent_portfolio.rb'),
               '--output', str(source_root)]
    for shape in sorted(set(tuple(s) for s in shapes)):
        command.extend(('--only', 'x'.join(map(str, shape))))
    subprocess.run(command, check=True, capture_output=True, text=True)


def local_seeds():
    seeds = {}
    library = ROOT / 'bits/tungsten-metaflip/lib/metaflip/seeds/gf2'
    for path in library.glob('matmul_*_gf2.txt'):
        match = re.match(r'matmul_([0-9]+x[0-9]+(?:x[0-9]+)?)_rank([0-9]+)', path.name)
        if not match:
            continue
        shape = tuple(map(int, match.group(1).split('x')))
        if len(shape) == 2:
            shape = (shape[0], shape[0], shape[1])
        key, rank = tuple(sorted(shape)), int(match.group(2))
        seeds[key] = min(seeds.get(key, rank), rank)
    for shape, _, rank, _, _ in CANDIDATES:
        key = tuple(sorted(shape))
        seeds[key] = min(seeds.get(key, rank), rank)
    for entry in json.loads(MANIFEST.read_text())['rows']:
        key, rank = tuple(entry['shape']), entry['rank']
        seeds[key] = min(seeds.get(key, rank), rank)
    for name in ('certified-block-extensions-20260923',
                 'certified-portfolio-extensions-20260923',
                 'block47-exact-20260923'):
        path = CERTIFICATES / name / 'manifest.json'
        for entry in json.loads(path.read_text())['rows']:
            key, rank = tuple(entry['shape']), entry['rank']
            seeds[key] = min(seeds.get(key, rank), rank)
    return seeds


def screen(digest, source_root):
    public = {}
    for entry in digest['entries']:
        key, rank = tuple(sorted(entry['format'])), entry['rank']
        if key in public and public[key] != rank:
            raise ValueError(f'conflicting public rank for {key}')
        public[key] = rank
    baseline = solver(local_seeds())
    best = {}
    projections = 0
    for entry in json.loads(MANIFEST.read_text())['rows']:
        pin = dict(source_portfolio_shape=entry['shape'],
                   source_shape=entry['result_shape'],
                   source_scheme_sha256=entry['result_sha256'])
        shape, terms = load_source(pin, source_root)
        for dimension, extent in enumerate(shape):
            for coordinate in range(extent):
                projections += 1
                target, projected = project(shape, terms, dimension, coordinate)
                key = tuple(sorted(target))
                if key not in public:
                    continue
                width = max(target[0] * target[1], target[1] * target[2], target[0] * target[2])
                cleaned, history = compress_shared(projected, max_bits=width)
                rank = len(cleaned)
                if rank >= min(public[key], baseline(key)):
                    continue
                row = dict(shape=list(key), rank=rank, raw_rank=len(projected),
                           cleanup_steps=len(history), public_rank=public[key],
                           local_baseline_rank=baseline(key), dimension=dimension,
                           deleted_coordinate=coordinate, **pin)
                choice = (rank, tuple(entry['shape']), dimension, coordinate)
                if key not in best or choice < best[key][0]:
                    best[key] = choice, row
    rows = sorted((row for _, row in best.values()), key=lambda row: (row['rank']-row['public_rank'], row['shape']))
    return dict(field='GF(2)', record_claim=False, projections=projections,
                source_parents=len(json.loads(MANIFEST.read_text())['rows']), rows=rows)


def screen_descendants(digest, output_dir, rows, extensions):
    public = {tuple(sorted(entry['format'])): entry['rank'] for entry in digest['entries']}
    seeds = local_seeds()
    frontier = []
    for row in list(rows) + list(extensions):
        key = tuple(row['shape'])
        seeds[key] = min(seeds.get(key, row['rank']), row['rank'])
        frontier.append(Path(row['output']))
    descendants = []
    scans = []
    generation = 2
    while frontier:
        baseline = solver(dict(seeds))
        best = {}
        projection_count = 0
        for parent_path in frontier:
            parent_raw = parent_path.read_bytes()
            parent_shape, terms = read_blob(parent_raw)
            parent_sha256 = hashlib.sha256(parent_raw).hexdigest()
            for dimension, extent in enumerate(parent_shape):
                for coordinate in range(extent):
                    projection_count += 1
                    target, projected = project(parent_shape, terms, dimension, coordinate)
                    key = tuple(sorted(target))
                    if key not in public:
                        continue
                    width = max(target[0] * target[1], target[1] * target[2], target[0] * target[2])
                    cleaned, history = compress_shared(projected, max_bits=width)
                    rank = len(cleaned)
                    if rank >= min(public[key], baseline(key)):
                        continue
                    row = dict(generation=generation, shape=list(key), rank=rank,
                               raw_rank=len(projected), cleanup_steps=len(history),
                               public_rank=public[key], local_baseline_rank=baseline(key),
                               dimension=dimension, deleted_coordinate=coordinate,
                               parent_shape=list(parent_shape), parent_rank=len(terms),
                               parent_sha256=parent_sha256)
                    choice = (rank, parent_sha256, dimension, coordinate)
                    if key not in best or choice < best[key][0]:
                        best[key] = choice, row
        scans.append(projection_count)
        frontier = []
        for _, row in sorted(best.values(), key=lambda pair: pair[1]['shape']):
            result = materialize_descendant(row, output_dir, output_dir)
            descendants.append(result)
            key = tuple(row['shape'])
            seeds[key] = min(seeds.get(key, row['rank']), row['rank'])
            frontier.append(Path(result['output']))
        generation += 1
    return descendants, scans


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--digest', type=Path, help='external fmm_sota.json for a complete finite screen')
    group.add_argument('--replay-manifest', type=Path, help='pin file containing retained projection rows')
    parser.add_argument('--output-dir', type=Path, help='new directory for exact full tensor witnesses')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='metaflip-structured-projection-') as tmp:
        source_root = Path(tmp) / 'sources'
        if args.replay_manifest:
            if args.output_dir is None:
                parser.error('--replay-manifest requires --output-dir')
            data = json.loads(args.replay_manifest.read_text())
            rows = data['rows']
            replay_sources(source_root, (row['source_portfolio_shape'] for row in rows))
        else:
            digest = json.loads(args.digest.read_text())
            replay_sources(source_root, (row['shape'] for row in json.loads(MANIFEST.read_text())['rows']))
            data = screen(digest, source_root)
            rows = data['rows']
        if args.output_dir:
            args.output_dir.mkdir(parents=True, exist_ok=False)
            rows = [materialize(row, source_root, args.output_dir) for row in rows]
            if args.replay_manifest:
                selected_extensions = data.get('extensions', ())
            else:
                available = {row['sha256'] for row in rows}
                public = {tuple(sorted(entry['format'])): entry['rank']
                          for entry in digest['entries']}
                selected_extensions = [row for row in json.loads(KNOWN_PROJECTIONS.read_text())['extensions']
                                       if row['large_projection_sha256'] in available and
                                       row['rank'] < public.get(tuple(row['shape']), row['rank'])]
            extensions = [materialize_extension(row, args.output_dir, args.output_dir)
                          for row in selected_extensions]
            if args.replay_manifest:
                descendants = [materialize_descendant(row, args.output_dir, args.output_dir)
                               for row in sorted(data.get('descendants', ()),
                                                 key=lambda row: row['generation'])]
                recursive_scans = data.get('recursive_scans', ())
            else:
                descendants, recursive_scans = screen_descendants(
                    digest, args.output_dir, rows, extensions)
        else:
            extensions = data.get('extensions', ())
            descendants = data.get('descendants', ())
            recursive_scans = data.get('recursive_scans', ())
        print(json.dumps(dict(data, rows=rows, extensions=extensions,
                              descendants=descendants,
                              recursive_scans=recursive_scans), indent=2))


if __name__ == '__main__':
    main()
