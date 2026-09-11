#!/usr/bin/env python3
"""Independent matrix-action oracle for the native GL(2,2)^3 parent cache."""
from hashlib import sha256
from itertools import product
from pathlib import Path
import subprocess
import sys

from refinement_worker_parity_test import exact
from verify_representation_portfolio import parse_terms


def mul(a, b):
    return tuple(sum(a[2*i+k]*b[2*k+j] for k in range(2)) % 2
                 for i in range(2) for j in range(2))


def transpose(a):
    return a[0], a[2], a[1], a[3]


def inverse(a):
    return a[3], a[1], a[2], a[0]  # determinant one, characteristic two


def transform(mask, left, right):
    matrix = tuple((mask >> i) & 1 for i in range(4))
    return sum(v << i for i, v in enumerate(mul(mul(left, matrix), right)))


result = subprocess.run([sys.argv[1]], check=True, capture_output=True, text=True, timeout=30)
root = Path(next(line.split(' ', 1)[1] for line in result.stdout.splitlines()
                 if line.startswith('ORBIT_ROOT ')))
seed = Path(__file__).resolve().parents[1] / 'lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt'
terms = parse_terms(seed.read_bytes(), 7)
gl = [a for a in product(range(2), repeat=4) if (a[0]*a[3]+a[1]*a[2]) % 2]
expected = set()
for a, b, c in product(gl, repeat=3):
    image = tuple(sorted((transform(u, a, b), transform(v, inverse(b), c),
                          transform(w, transpose(inverse(a)), transpose(inverse(c))))
                         for u, v, w in terms))
    exact((2, 2, 2), image)
    expected.add(image)
actual = set()
for path in (root / 'objects').glob('*.tensor'):
    raw = path.read_bytes()
    assert sha256(raw).hexdigest() == path.stem
    lines = raw.decode().splitlines()
    assert lines[0] == 'MFR1 2 2 2 7'
    image = tuple(tuple(map(int, line.split())) for line in lines[1:])
    exact((2, 2, 2), image)
    actual.add(image)
assert actual == expected and len(actual) == 36
assert (root / 'submitted').read_text() == '36\n'
print(result.stdout.strip())
print('PASS independent matrix-action orbit equality, hashes and all 36 full tensor identities')
