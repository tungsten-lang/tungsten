#!/usr/bin/env python3
"""Independent bit-grid parity for every packed axis-mask projection."""
import argparse
from pathlib import Path
import random
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import screen_top_two_projection_children as top
from packed_composition_parity_test import naive

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


def shear_terms(shape, terms, axis, removed, mask):
    affected = [k for k, edge in enumerate(EDGES) if axis in edge]
    assert len(affected) == 2 and not (mask >> removed) & 1
    result = []
    for term in terms:
        factors = list(term)
        for b in range(shape[axis]):
            if not (mask >> b) & 1:
                continue
            for order, k in enumerate(affected):
                edge = EDGES[k]
                dst, src = (removed, b) if order == 0 else (b, removed)
                factors[k] = shear_word(factors[k], shape[edge[0]], shape[edge[1]],
                                        edge.index(axis), dst, src)
        result.append(tuple(factors))
    return result


def check(binary):
    rng = random.Random(20260923)
    cases = 0
    with tempfile.TemporaryDirectory(prefix='metaflip-axis-mask-') as temp:
        source, output = (Path(temp) / name for name in ('source.mfw', 'output.mfw'))
        for shape in ((2, 3, 2), (3, 2, 33), (1, 2, 512), (4, 7, 4), (32, 32, 32)):
            if max(shape) <= 33:
                terms = naive(shape) if shape[0]*shape[1]*shape[2] <= 200 else []
            else:
                terms = []
            if not terms:
                widths = (shape[0]*shape[1], shape[1]*shape[2], shape[0]*shape[2])
                terms = sorted({tuple(sum(1 << bit for bit in rng.sample(
                    range(width), rng.randint(1, min(5, width)))) for width in widths)
                    for _ in range(20)})
            source.write_bytes(top.blob(shape, terms))
            for axis, size in enumerate(shape):
                if size < 2 or size > 32:
                    continue
                for removed in sorted({0, size//2, size-1}):
                    others = [v for v in range(size) if v != removed]
                    for rows in ((), (others[0],), tuple(others[:3])):
                        mask = sum(1 << b for b in rows)
                        changed = shear_terms(shape, terms, axis, removed, mask)
                        if shape[0]*shape[1]*shape[2] <= 200:
                            top.exact(shape, changed)
                        target, expected = top.project(shape, changed, axis, removed)
                        run = subprocess.run([str(binary), '--axis-mask', str(source),
                                              str(output), str(axis), str(removed), str(mask)],
                                             check=True, capture_output=True, text=True, timeout=30)
                        actual_shape, actual = top.read_blob(output.read_bytes())
                        assert actual_shape == target and actual == expected
                        assert run.stdout.split() == ['WIDE_AXIS_MASK', str(len(terms)),
                                                      str(len(actual))]
                        if shape[0]*shape[1]*shape[2] <= 200:
                            top.exact(target, actual)
                        cases += 1
        source.write_bytes(top.blob((2, 3, 2), naive((2, 3, 2))))
        for axis, removed, mask in ((-1, 0, 0), (3, 0, 0), (0, -1, 0),
                                    (2, 2, 0), (1, 0, 1), (2, 0, -1)):
            output.unlink(missing_ok=True)
            run = subprocess.run([str(binary), '--axis-mask', str(source), str(output),
                                  str(axis), str(removed), str(mask)],
                                 capture_output=True, text=True, timeout=10)
            assert run.returncode != 0 and not output.exists()
    print(f'PASS packed axis-mask projection: {cases} independent cases')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    args = parser.parse_args()
    check(args.binary.resolve())
