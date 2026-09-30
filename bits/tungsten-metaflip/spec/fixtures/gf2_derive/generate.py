#!/usr/bin/env python3
"""Regenerates spec/fixtures/gf2_derive/ from the ORIGINAL Python functions (the oracles).

  generate.py

writes, next to this file:

  in/<name>.txt        the input schemes (copies of seed files of lib/metaflip/seeds/gf2, and two derived schemes whose
                       terms are split so that shared-factor compression has something to merge), decimal `R u v w` rows
  in/shapes.tsv        name and shape of every input
  expected/cases.tsv   one row per case: name, result rank, SHA-256 of the result's terms as `u v w` hexadecimal lines in the
                       ORDER the original returns them (so an order difference fails), for
                         block:<scheme>:<target>:<offsets>          verify_composition_targets.block
                         kron:<a>:<b>                               verify_composition_targets.kronecker
                         project:<scheme>:<dimension>:<coordinate>  screen_structured_parent_projections.project
                         factors:<seed>:<reverse>                   verify_cofactor_mergers.matrix_factors on random pairs
                         compress:<scheme>                          compress_shared (terms, then its history)
                         refactor:<scheme>:<axis>:<reverse>         refactor_shared (terms, then the changed groups)
                         basis:<scheme>:<mode>                      two_pass, modes 6..17
                         child:<scheme>:<axis>:<coordinate>         project, then compress_shared at the width of the smaller shape

Everything here is derived from the Python originals, never from the Tungsten port.
"""
import hashlib
import os
import random
import shutil
import sys
from itertools import product
from pathlib import Path

HERE = Path(__file__).resolve().parent
BIT = HERE.parents[2]
sys.path[:0] = [str(BIT / 'tools'), str(BIT.parents[1] / 'benchmarks/matmul/metaflip')]
os.environ.setdefault('PYTHONDONTWRITEBYTECODE', '1')
from verify_composition_targets import block, kronecker  # noqa: E402
from verify_cofactor_mergers import compress_shared, matrix_factors, refactor_shared  # noqa: E402
from screen_structured_parent_projections import project  # noqa: E402
from screen_two_pass_basis_children import two_pass  # noqa: E402

SEEDS = BIT / 'lib/metaflip/seeds/gf2'
PICK = {
    'strassen': ('2x2x2', 'matmul_2x2_rank7_strassen_gf2.txt'),
    's234': ('2x3x4', 'matmul_2x3x4_rank20_d130_global_isotropy_gf2.txt'),
    's225': ('2x2x5', 'matmul_2x2x5_rank18_d84_gf2.txt'),
    's235p2': ('2x3x5', 'matmul_2x3x5_rank27_peterson_2026_isotropy_split_plus2_parent_06df603ec6_gf2.txt'),
    's256': ('2x5x6', 'matmul_2x5x6_rank47_catalog_gf2.txt'),
}


def read(path):
    rows = [tuple(map(int, line.split()[-3:])) for line in path.read_text().splitlines()
            if line.strip() and not line.startswith('#') and len(line.split()) >= 3 and not line.strip().isdigit()]
    return rows


def lines(terms):
    return ''.join(f'{u:x} {v:x} {w:x}\n' for u, v, w in terms)


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def split_terms(terms, seed):
    """Replace some terms (a, b, c) by two terms that share b and c, with a1 ^ a2 = a: compress_shared can merge them back."""
    rng = random.Random(seed)
    out = []
    for u, v, w in terms:
        if rng.random() < 0.4 and bin(u).count('1') >= 2:
            low = u & -u
            out.append((low, v, w))
            out.append((u ^ low, v, w))
        else:
            out.append((u, v, w))
    return out


shutil.rmtree(HERE / 'in', ignore_errors=True)
shutil.rmtree(HERE / 'expected', ignore_errors=True)
(HERE / 'in').mkdir()
(HERE / 'expected').mkdir()
schemes = {}
for name, (shape, file) in PICK.items():
    schemes[name] = (tuple(map(int, shape.split('x'))), read(SEEDS / file))
    shutil.copy(SEEDS / file, HERE / 'in' / f'{name}.txt')
for name, (base, seed) in {'strassen_split': ('strassen', 1), 's234_split': ('s234', 2), 's256_split': ('s256', 3)}.items():
    shape, terms = schemes[base]
    schemes[name] = (shape, split_terms(terms, seed))
    (HERE / 'in' / f'{name}.txt').write_text(''.join(f'R {u} {v} {w}\n' for u, v, w in schemes[name][1]))
(HERE / 'in' / 'shapes.tsv').write_text(''.join(f'{n}\t{"x".join(map(str, s))}\t{len(t)}\n' for n, (s, t) in schemes.items()))

rows = []


def record(name, terms, extra=''):
    rows.append((name, len(terms), digest(lines(terms) + extra)))


# block
for name in ('strassen', 's234', 's256'):
    shape, terms = schemes[name]
    for target, offsets in [((shape[0] + 1, shape[1] + 2, shape[2] + 3), (0, 0, 0)), ((shape[0] + 2, shape[1] + 1, shape[2] + 1), (1, 0, 1)),
                            ((shape[0] * 2, shape[1], shape[2] * 2), (shape[0], 0, shape[2]))]:
        record(f'block:{name}:{"x".join(map(str, target))}:{"".join(map(str, offsets))}', block(shape, terms, target, offsets))
# kronecker
for a, b in [('strassen', 'strassen'), ('strassen', 's234'), ('s225', 'strassen'), ('s234', 's225')]:
    record(f'kron:{a}:{b}', kronecker(schemes[a][0], schemes[a][1], schemes[b][0], schemes[b][1]))
# project
for name in ('strassen', 's234', 's225', 's235p2'):
    shape, terms = schemes[name]
    for dimension in range(3):
        for coordinate in range(shape[dimension]):
            new_shape, new_terms = project(shape, terms, dimension, coordinate)
            record(f'project:{name}:{dimension}:{coordinate}', new_terms, 'x'.join(map(str, new_shape)) + '\n')
# matrix_factors on random pairs
rng = random.Random(7)
for trial in range(12):
    bits = rng.choice([8, 40, 70])
    pairs = [(rng.getrandbits(bits) | 1, rng.getrandbits(bits) | 1) for _ in range(rng.randint(2, 9))]
    if trial % 3 == 0:  # dependent columns: repeat a left factor
        pairs = [(pairs[0][0], r) for _, r in pairs]
    for reverse in (False, True):
        try:
            factors = matrix_factors(pairs, max_bits=128, reverse_columns=reverse)
            record(f'factors:{trial}:{int(reverse)}', [(l, r, 1) for l, r in factors])
        except AssertionError as error:
            rows.append((f'factors:{trial}:{int(reverse)}', -1, digest(str(error))))
    (HERE / 'in' / f'pairs_{trial}.txt').write_text(''.join(f'{l} {r}\n' for l, r in pairs))
# compress_shared and refactor_shared
for name, (shape, terms) in schemes.items():
    big = max(u.bit_length() for t in terms for u in t)
    compressed, history = compress_shared(terms, max_bits=max(256, big))
    record(f'compress:{name}', compressed, ''.join(f"{h['axis']} {h['fixed']:x} {h['before']} {h['after']}\n" for h in history))
    for axis in range(3):
        for reverse in (False, True):
            out, changed = refactor_shared(terms, axis, max_bits=max(256, big), reverse_columns=reverse)
            record(f'refactor:{name}:{axis}:{int(reverse)}', out,
                   ''.join(f"{c['fixed']:x} {c['before']} {c['after']}\n" for c in changed))
for name, (shape, terms) in schemes.items():
    if name in ('strassen', 's234', 's225', 's235p2', 's256', 's234_split'):
        for mode in range(6, 18):
            record(f'basis:{name}:{mode}', two_pass(terms, shape, mode))
for name in ('s234', 's235p2', 's234_split'):
    shape, terms = schemes[name]
    for axis in range(3):
        for coordinate in (0, shape[axis] - 1):
            target, raw = project(shape, terms, axis, coordinate)
            width = max(target[0] * target[1], target[1] * target[2], target[0] * target[2])
            child, history = compress_shared(raw, max_bits=width)
            record(f'child:{name}:{axis}:{coordinate}', child, 'x'.join(map(str, target)) + '\n' +
                   ''.join(f"{h['axis']} {h['fixed']:x} {h['before']} {h['after']}\n" for h in history))
(HERE / 'expected' / 'cases.tsv').write_text(''.join(f'{n}\t{r}\t{d}\n' for n, r, d in rows))
print(len(rows), 'cases')
