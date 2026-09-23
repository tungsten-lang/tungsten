#!/usr/bin/env python3
"""Replay pinned GF(2) axis-mask descendants and verify every whole tensor."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

import replay_middle_mask_cascade as source_replay
import screen_neutral_basis_children as neutral
import screen_top_two_projection_children as top
from wide_matrix_cleanup_parity_test import read_blob

HERE = Path(__file__).resolve().parent
DEFAULT_MANIFEST = HERE / 'certificates/axis-mask-cascades-20260923/8x17x30-8x17x29.json'
EDGES = ((0, 1), (1, 2), (0, 2))


def shear_word(word, rows, cols, dimension, dst, src):
    result = word
    if dimension == 0:
        for col in range(cols):
            result ^= ((word >> (src * cols + col)) & 1) << (dst * cols + col)
    else:
        for row in range(rows):
            result ^= ((word >> (row * cols + src)) & 1) << (row * cols + dst)
    return result


def child(shape, terms, axis, removed, mask):
    if (axis not in range(3) or not 0 <= removed < shape[axis] or mask < 0 or
            mask >= 1 << shape[axis] or (mask >> removed) & 1):
        raise ValueError('invalid axis mask')
    incident = [k for k, edge in enumerate(EDGES) if axis in edge]
    changed = []
    for term in terms:
        factors = list(term)
        for bit in range(shape[axis]):
            if not (mask >> bit) & 1:
                continue
            for order, k in enumerate(incident):
                edge = EDGES[k]
                dst, src = ((removed, bit) if order == 0 else (bit, removed))
                factors[k] = shear_word(factors[k], shape[edge[0]], shape[edge[1]],
                                        edge.index(axis), dst, src)
        changed.append(tuple(factors))
    top.exact(shape, changed)
    target, raw = top.project(shape, changed, axis, removed)
    keep = [list(range(size)) for size in shape]
    keep[axis].pop(removed)
    if raw != neutral.project_grid(shape, changed, keep):
        raise ValueError('independent projection mismatch')
    width = max(target[0] * target[1], target[1] * target[2], target[0] * target[2])
    cleaned, history = top.compress_shared(raw, max_bits=width)
    top.exact(target, cleaned)
    return target, raw, cleaned, history


def replay(manifest, output_dir=None):
    if (manifest.get('schema') != 1 or manifest.get('field') != 'GF(2)' or
            manifest.get('record_claim') is not False or
            not isinstance(manifest.get('steps'), list) or not manifest['steps']):
        raise ValueError('invalid manifest')
    with tempfile.TemporaryDirectory(prefix='metaflip-axis-mask-cascade-') as temp:
        root = Path(temp)
        parent = source_replay.replay_source(manifest['source'], root)
        payload = parent.read_bytes()
        shape, terms = read_blob(payload)
        source = manifest['source']
        if (hashlib.sha256(payload).hexdigest() != source['mfw_sha256'] or
                list(shape) != source['oriented_shape'] or len(terms) != source['rank']):
            raise ValueError('source pin mismatch')
        top.exact(shape, terms)
        if output_dir:
            output_dir.mkdir(parents=True, exist_ok=False)
        results = []
        for step in manifest['steps']:
            target, raw, cleaned, history = child(
                shape, terms, step['axis'], step['deleted_coordinate'], step['shear_mask'])
            payload = top.blob(target, cleaned)
            digest = hashlib.sha256(payload).hexdigest()
            if (list(target) != step['oriented_shape'] or
                    len(raw) != step['raw_rank'] or len(history) != step['cleanup_steps'] or
                    len(cleaned) != step['rank'] or digest != step['sha256']):
                raise ValueError('projection or cleanup mismatch')
            path = (output_dir or root) / (
                'x'.join(map(str, target)) + f'-r{len(cleaned)}-{digest[:12]}.mfw')
            path.write_bytes(payload)
            checked = json.loads(subprocess.check_output(
                ['ruby', str(HERE / 'verify_tensor.rb'), '--shape',
                 'x'.join(map(str, target)), str(path)], text=True))[0]
            if not checked['exact'] or checked['rank'] != len(cleaned) or checked['sha256'] != digest:
                raise ValueError('independent tensor verification failed')
            results.append({'shape': list(target), 'rank': len(cleaned), 'sha256': digest})
            shape, terms = target, cleaned
        return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument('--output-dir', type=Path)
    args = parser.parse_args()
    print(json.dumps(replay(json.loads(args.manifest.read_text()), args.output_dir), indent=2))


if __name__ == '__main__':
    main()
