#!/usr/bin/env python3
"""Compare packed middle-mask projection against independent GF(2) bit grids."""
import argparse
from hashlib import sha256
from pathlib import Path
import random
import subprocess
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import screen_middle_shear_children as shear
import screen_top_two_projection_children as top
from packed_composition_parity_test import naive


def check(binary, certified_source=None):
    binary = str(binary.resolve())
    rng = random.Random(634721)
    cases = 0
    with tempfile.TemporaryDirectory(prefix='metaflip-middle-mask-native-') as temp:
        source, output = (Path(temp) / name for name in ('source.mfw', 'output.mfw'))

        def parity(shape, terms, removed, mask):
            nonlocal cases
            source.write_bytes(top.blob(shape, terms))
            target, expected = top.project(
                shape, shear.shear_middle_mask(shape, terms, removed, mask), 1, removed)
            run = subprocess.run([binary, '--middle-mask', str(source), str(output),
                                  str(removed), str(mask)], capture_output=True,
                                 text=True, check=True, timeout=30)
            result_shape, result = top.read_blob(output.read_bytes())
            assert result_shape == target and result == expected
            assert run.stdout.split() == ['WIDE_MIDDLE_MASK', str(len(terms)),
                                          str(len(result))]
            cases += 1
            return target, result

        for shape in ((2, 3, 2), (3, 2, 33), (1, 2, 512)):
            terms = naive(shape)
            top.exact(shape, terms)
            for removed in range(shape[1]):
                for mask in range(1 << shape[1]):
                    if (mask >> removed) & 1:
                        continue
                    target, result = parity(shape, terms, removed, mask)
                    top.exact(target, result)

        for shape in ((4, 7, 4), (32, 32, 32)):
            widths = (shape[0]*shape[1], shape[1]*shape[2], shape[0]*shape[2])
            terms = sorted({tuple(sum(1 << bit for bit in rng.sample(
                range(width), rng.randint(1, 5))) for width in widths)
                for _ in range(20)})
            for removed in (0, shape[1]//2, shape[1]-1):
                others = [v for v in range(shape[1]) if v != removed]
                for picks in ((), (others[0],), tuple(others[:3])):
                    parity(shape, terms, removed, sum(1 << v for v in picks))

        source.write_bytes(top.blob((2, 3, 2), naive((2, 3, 2))))
        for removed, mask in ((-1, 0), (3, 0), (0, -1), (0, 1), (0, 8)):
            output.unlink(missing_ok=True)
            run = subprocess.run([binary, '--middle-mask', str(source), str(output),
                                  str(removed), str(mask)], capture_output=True,
                                 text=True, timeout=10)
            assert run.returncode != 0 and not output.exists()

        if certified_source is not None:
            shape, terms = top.read_blob(certified_source.read_bytes())
            assert shape == (16, 24, 31) and len(terms) == 6484
            top.exact(shape, terms)
            target, result = parity(shape, terms, 12, 262209)
            assert len(result) == 6457
            width = max(target[0]*target[1], target[1]*target[2], target[0]*target[2])
            cleaned, history = top.compress_shared(result, max_bits=width)
            assert len(cleaned) == 6376 and len(history) == 55
            assert sha256(top.blob(target, cleaned)).hexdigest() == (
                '04867c5f5a06a2a914b622c81e9b422e54bdce8cfc43e5c2eaf17e447957f577')
            top.exact(target, cleaned)
    print(f'PASS wide middle-mask projection: {cases} parity cases, '
          f'certified={certified_source is not None}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('--certified-source', type=Path)
    args = parser.parse_args()
    check(args.binary, args.certified_source)
