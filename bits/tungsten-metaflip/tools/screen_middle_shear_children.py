#!/usr/bin/env python3
"""Screen exact middle-basis shears before coordinate projection over GF(2)."""
import argparse
import hashlib
from itertools import combinations
import json
from math import comb
from pathlib import Path
import subprocess
import tempfile

import screen_neutral_basis_children as neutral
import screen_top_two_projection_children as top
import screen_two_pass_basis_children as two_pass

HERE = Path(__file__).resolve().parent


def shear_middle_mask(shape, terms, a, mask):
    """Apply A[:,a] ^= sum A[:,b], B[b,:] ^= B[a,:] for b in mask."""
    n, m, p = shape
    if not 0 <= a < m or mask < 0 or mask >= 1 << m or (mask >> a) & 1:
        raise ValueError('invalid middle shear')
    row_mask = (1 << p) - 1
    spread = sum(1 << (b * p) for b in range(m) if (mask >> b) & 1)
    result = []
    for left, right, out in terms:
        x = left
        for i in range(n):
            x ^= (((left >> (i * m)) & mask).bit_count() & 1) << (i * m + a)
        y = right ^ (((right >> (a * p)) & row_mask) * spread)
        result.append((x, y, out))
    return result


def shear_middle(shape, terms, a, b):
    if a == b or not 0 <= b < shape[1]:
        raise ValueError('invalid middle shear')
    return shear_middle_mask(shape, terms, a, 1 << b)


def child_mask(shape, terms, a, mask, *, independent=False):
    changed = shear_middle_mask(shape, terms, a, mask)
    if independent:
        top.exact(shape, changed)
    target, projected = top.project(shape, changed, 1, a)
    if independent:
        keep = [list(range(v)) for v in shape]
        keep[1].pop(a)
        if projected != neutral.project_grid(shape, changed, keep):
            raise ValueError('independent projection mismatch')
    width = max(target[0] * target[1], target[1] * target[2], target[0] * target[2])
    result, history = top.compress_shared(projected, max_bits=width)
    if independent:
        top.exact(target, result)
    return target, projected, result, history


def child(shape, terms, a, b, *, independent=False):
    if a == b or not 0 <= b < shape[1]:
        raise ValueError('invalid middle shear')
    return child_mask(shape, terms, a, 1 << b, independent=independent)


def source(parents, digest):
    matches = [row for row in parents if row['sha256'] == digest]
    if len(matches) != 1:
        raise ValueError('missing or ambiguous pinned source')
    return two_pass.source_row(matches[0])


def row_for(shape, terms, digest, a, mask, target, raw, result, history):
    payload = top.blob(target, result)
    return dict(source_shape=list(shape), source_rank=len(terms), source_sha256=digest,
                shear_mask=mask, mix_rows=[b for b in range(shape[1]) if (mask >> b) & 1],
                axis=1, deleted_coordinate=a,
                raw_rank=len(raw), cleanup_steps=len(history),
                oriented_shape=list(target), shape=sorted(target), rank=len(result),
                sha256=hashlib.sha256(payload).hexdigest())


def screen(shape, terms, digest):
    best = None
    contexts = 0
    # First identify the strongest one-row shear and its deleted coordinate.
    for a in range(shape[1]):
        for b in range(shape[1]):
            if a == b:
                continue
            mask = 1 << b
            target, raw, result, history = child_mask(shape, terms, a, mask)
            row = row_for(shape, terms, digest, a, mask, target, raw, result, history)
            contexts += 1
            if best is None or (row['rank'], row['sha256']) < (best['rank'], best['sha256']):
                best = row
    selected_a = best['deleted_coordinate']
    others = [b for b in range(shape[1]) if b != selected_a]
    # Singletons for this coordinate were already visited in the first phase.
    for weight in (0, 2, 3):
        for rows in combinations(others, weight):
            mask = sum(1 << b for b in rows)
            target, raw, result, history = child_mask(shape, terms, selected_a, mask)
            row = row_for(shape, terms, digest, selected_a, mask,
                          target, raw, result, history)
            contexts += 1
            if (row['rank'], row['sha256']) < (best['rank'], best['sha256']):
                best = row
    child_mask(shape, terms, best['deleted_coordinate'], best['shear_mask'],
               independent=True)
    return dict(schema=1, field='GF(2)', record_claim=False,
                parent_set='composed-descendants', selected_deleted=selected_a,
                max_mix_rows=3, contexts=contexts, row=best)


def replay(data, shape, terms, digest, output_dir):
    if (data['schema'] != 1 or data['field'] != 'GF(2)' or data['record_claim'] or
            data['parent_set'] != 'composed-descendants' or
            data['max_mix_rows'] != 3 or
            data['contexts'] != shape[1] * (shape[1] - 1) + 1 +
            comb(shape[1] - 1, 2) + comb(shape[1] - 1, 3)):
        raise ValueError('invalid manifest header')
    row = data['row']
    if (row['source_sha256'] != digest or row['source_shape'] != list(shape) or
            row['source_rank'] != len(terms) or row['axis'] != 1 or
            row['deleted_coordinate'] != data['selected_deleted'] or
            row['shear_mask'].bit_count() > data['max_mix_rows'] or
            row['mix_rows'] != [b for b in range(shape[1])
                                if (row['shear_mask'] >> b) & 1]):
        raise ValueError('source or operation mismatch')
    a, mask = row['deleted_coordinate'], row['shear_mask']
    target, raw, result, history = child_mask(shape, terms, a, mask, independent=True)
    if row_for(shape, terms, digest, a, mask, target, raw, result, history) != row:
        raise ValueError('result or cleanup mismatch')
    output_dir.mkdir(parents=True, exist_ok=False)
    output = output_dir / ('x'.join(map(str, target)) + f'-r{len(result)}-{row["sha256"][:12]}.mfw')
    output.write_bytes(top.blob(target, result))
    checked = json.loads(subprocess.check_output(
        ['ruby', str(HERE / 'verify_tensor.rb'), '--shape',
         'x'.join(map(str, target)), str(output)], text=True))[0]
    if not checked['exact'] or checked['rank'] != row['rank'] or checked['sha256'] != row['sha256']:
        raise ValueError('independent full-tensor verification failed')
    return dict(data, output=str(output))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--screen-source-sha256')
    mode.add_argument('--replay-manifest', type=Path)
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--manifest-path', type=Path)
    args = parser.parse_args()
    if args.replay_manifest and args.output_dir is None:
        parser.error('--replay-manifest requires --output-dir')
    if args.replay_manifest and args.manifest_path:
        parser.error('--manifest-path is only for screening')
    manifest = json.loads(args.replay_manifest.read_text()) if args.replay_manifest else None
    digest = args.screen_source_sha256 or manifest['row']['source_sha256']
    with tempfile.TemporaryDirectory(prefix='metaflip-middle-shear-') as temp:
        parents = two_pass.build_parents(Path(temp) / 'parents', 'composed-descendants')
        shape, terms, digest = source(parents, digest)
        data = manifest or screen(shape, terms, digest)
        manifest_data = data
        if args.output_dir:
            data = replay(data, shape, terms, digest, args.output_dir)
        if args.manifest_path:
            args.manifest_path.parent.mkdir(parents=True, exist_ok=True)
            args.manifest_path.write_text(json.dumps(manifest_data, indent=2) + '\n')
        print(json.dumps(data, indent=2))


if __name__ == '__main__':
    main()
