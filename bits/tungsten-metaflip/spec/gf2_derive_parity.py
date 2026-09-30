#!/usr/bin/env python3
"""Parity of tools/scheme_ops.w (lib/metaflip/gf2/derive.w) with the Python originals on real tensors.

  gf2_derive_parity.py --corpus DIR --binary ./scheme_ops [--limit N]

DIR is a port corpus (corpus.tsv and mfw/<sha256>.mfw). For a spread of tensors of the campaign (ranks 100 to 1,600) every
operation is run by the original (in this process) and by the binary, and the SHA-256 of the canonical MFW1 of the two results
is compared: project (three coordinates of each axis), child (project, then compress: the unreduced children of the screens),
compress (compress_shared), rewrite (refactor_shared along axis 0 and 1, reverse order on axis 2), basis (two-pass modes 6, 7, 13
and 17), kron with Strassen, block (placed inside a larger shape). Prints `n agree of n compared` and the
first mismatches; exit status 1 on any.
"""
import argparse
import hashlib
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
BIT = HERE.parent
sys.path[:0] = [str(BIT / 'tools'), str(BIT.parents[1] / 'benchmarks/matmul/metaflip')]
os.environ.setdefault('PYTHONDONTWRITEBYTECODE', '1')
from verify_composition_targets import block, kronecker  # noqa: E402
from verify_cofactor_mergers import compress_shared, refactor_shared  # noqa: E402
from screen_structured_parent_projections import project  # noqa: E402
from screen_two_pass_basis_children import two_pass  # noqa: E402
from wide_matrix_cleanup_parity_test import blob, read_blob  # noqa: E402

SHAPES = ['2x4x17', '4x4x14', '4x5x16', '8x8x9', '9x9x9', '8x8x16', '12x8x12', '9x10x14', '9x11x13', '3x14x25']


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    parser.add_argument('--corpus', required=True)
    parser.add_argument('--binary', required=True)
    parser.add_argument('--limit', type=int, default=len(SHAPES))
    args = parser.parse_args()
    corpus = Path(args.corpus)
    rows = [line.split('\t') for line in (corpus / 'corpus.tsv').read_text().splitlines()[1:]]
    chosen = {}
    for sha, shape, rank, source in rows:
        if shape in SHAPES[:args.limit] and shape not in chosen and 100 <= int(rank) <= 1600:
            chosen[shape] = sha
    strassen = Path(BIT / 'lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt')
    s_terms = [tuple(map(int, l.split()[1:])) for l in strassen.read_text().splitlines() if l.startswith('R ')]
    s_path = Path('/tmp/strassen_2x2x2_parity.mfw')
    s_path.write_bytes(blob((2, 2, 2), s_terms))
    agree = compared = 0
    failures = []
    times = {'python': 0.0, 'tungsten': 0.0}

    def check(label, original, arguments):
        nonlocal agree, compared
        t0 = time.process_time()
        expected = hashlib.sha256(original()).hexdigest()
        times['python'] += time.process_time() - t0
        t0 = time.time()
        run = subprocess.run([args.binary, *arguments], capture_output=True)
        times['tungsten'] += time.time() - t0
        got = hashlib.sha256(run.stdout).hexdigest() if run.returncode == 0 else f'status {run.returncode}: {run.stderr[:80]!r}'
        compared += 1
        if got == expected:
            agree += 1
        else:
            failures.append(label)
            print('MISMATCH', label, got[:30], expected[:12], flush=True)

    for shape_text, sha in chosen.items():
        path = corpus / 'mfw' / f'{sha}.mfw'
        shape, terms = read_blob(path.read_bytes())
        width = max(shape[0] * shape[1], shape[1] * shape[2], shape[0] * shape[2])
        for dimension in range(3):
            for coordinate in (0, shape[dimension] // 2, shape[dimension] - 1):
                check(f'project {shape_text} {dimension} {coordinate}',
                      lambda: blob(*project(shape, terms, dimension, coordinate)),
                      ['project', str(path), str(dimension), str(coordinate)])
        for dimension in range(3):
            coordinate = shape[dimension] // 2
            def child():
                target, raw = project(shape, terms, dimension, coordinate)
                return blob(target, compress_shared(raw, max_bits=max(target[0] * target[1], target[1] * target[2], target[0] * target[2]))[0])
            check(f'child {shape_text} {dimension} {coordinate}', child, ['child', str(path), str(dimension), str(coordinate)])
        for mode in (6, 7, 13, 17):
            check(f'basis {shape_text} {mode}', lambda: blob(shape, two_pass(terms, shape, mode)), ['basis', str(path), str(mode)])
        check(f'compress {shape_text}', lambda: blob(shape, compress_shared(terms, max_bits=max(256, width))[0]),
              ['compress', str(path)])
        for axis, reverse in ((0, False), (1, False), (2, True)):
            check(f'rewrite {shape_text} {axis} {int(reverse)}',
                  lambda: blob(shape, refactor_shared(terms, axis, max_bits=max(256, width), reverse_columns=reverse)[0]),
                  ['rewrite', str(path), str(axis)] + (['reverse'] if reverse else []))
        if len(terms) <= 800:
            check(f'kron {shape_text}', lambda: blob(tuple(a * b for a, b in zip(shape, (2, 2, 2))),
                                                    kronecker(shape, terms, (2, 2, 2), s_terms)),
                  ['kron', str(path), str(s_path)])
        target = tuple(d + 2 for d in shape)
        check(f'block {shape_text}', lambda: blob(target, block(shape, terms, target, (1, 0, 2))),
              ['block', str(path), *map(str, target), '1', '0', '2'])
        print(shape_text, len(terms), 'done', flush=True)
    print(f'{agree} agree of {compared} compared; original {times["python"]:.1f} s CPU, binary {times["tungsten"]:.1f} s wall')
    return 0 if agree == compared else 1


if __name__ == '__main__':
    sys.exit(main())
