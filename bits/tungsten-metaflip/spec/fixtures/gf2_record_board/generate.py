#!/usr/bin/env python3
"""Regenerates spec/fixtures/gf2_record_board/ from the ORIGINAL tool (tools/gf2_record_board.py, the oracle).

  generate.py

writes, next to this file:

  in/                 the inputs: two public tables (lille.json, catalog.json), a directory of FMM-format file names
                      (extra/), and a tree of witness files of every format the board reads (MFW1, .gz.b64,
                      decimal with and without a rank line and `R ` prefixes, schemes stored in another orientation than
                      the name suggests, an inexact one, an unsorted MFW1, a hidden directory)
  expected/dims.tsv     re.search(r'(\\d+)x(\\d+)(?:x(\\d+))?', name) of assorted names and the shape_hint the tool derives
  expected/ring.tsv     the FMM file-name pattern of the tool on assorted names: key, ring, rank or None
  expected/decode.tsv   what the tool's decode answers for every witness file: shape and rank, or None
  expected/rows.json    the rows the tool writes for the whole tree, paths relative to in/ (the tool's absolute
                        fixture path is replaced by @FIX@), expected/cache.json the verdicts, summary.txt and
                        verbose.txt its standard output

Everything here is derived from the Python original, never from the Tungsten port.
"""
import base64
import gzip
import json
import os
import re
import shutil
import subprocess
import sys
from itertools import product
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parents[2] / 'tools'
sys.path.insert(0, str(TOOLS))
os.environ.setdefault('PYTHONDONTWRITEBYTECODE', '1')
import gf2_record_board as grb  # noqa: E402

IN = HERE / 'in'
OUT = HERE / 'expected'
SEED = HERE.parents[2] / 'lib' / 'metaflip' / 'seeds' / 'gf2' / 'matmul_2x2_rank7_d36_gl120_gf2.txt'


def naive(shape):
    n, m, p = shape
    return [(1 << (i * m + j), 1 << (j * p + k), 1 << (i * p + k)) for i, j, k in product(range(n), range(m), range(p))]


def blob(shape, terms, order=True):
    rows = sorted(terms) if order else list(terms)
    return (f'MFW1 {" ".join(map(str, shape))} {len(terms)}\n' +
            ''.join(' '.join(f'{v:x}' for v in t) + '\n' for t in rows)).encode()


def write(path, data):
    path = IN / path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data if isinstance(data, bytes) else data.encode())


def decimal(terms, header=False, prefix=''):
    return (f'{len(terms)}\n' if header else '') + ''.join(f'{prefix}{u} {v} {w}\n' for u, v, w in terms)


shutil.rmtree(IN, ignore_errors=True)
shutil.rmtree(OUT, ignore_errors=True)
OUT.mkdir()
strassen = [tuple(map(int, line.split()[1:])) for line in SEED.read_text().splitlines() if line.startswith('R ')]
assert len(strassen) == 7
flipped = [(strassen[0][0] ^ 1,) + strassen[0][1:]] + strassen[1:]

# public tables
write('lille.json', json.dumps({'entries': [
    {'format': [2, 2, 2], 'rank': 7}, {'format': [2, 2, 3], 'rank': 11}, {'format': [2, 3, 3], 'rank': 15},
    {'format': [3, 3, 4], 'rank': 40}, {'format': [3, 4, 4], 'rank': 47}]}, indent=1) + '\n')
write('catalog.json', json.dumps({'schemes': [
    {'format': [2, 2, 2], 'rank': 7, 'fields': ['F2', 'Q'], 'commutative': False},
    {'format': [3, 2, 3], 'rank': 15, 'fields': ['Q', 'R'], 'commutative': False},
    {'format': [3, 3, 3], 'rank': 21, 'fields': ['F3'], 'commutative': True},
    {'format': [4, 3, 3], 'rank': 41, 'fields': ['F2'], 'commutative': False},
    {'format': [4, 4, 3], 'rank': 50, 'fields': ['F2', 'Q'], 'commutative': False},
    {'format': [3, 3, 3], 'rank': 23, 'fields': ['F2', 'Q']}]}, indent=1) + '\n')
names = ['schemes/2x2x2_m7_ZT.json', 'schemes/known/3x3x3_m21_Z.json', 'schemes/3x3x4_m45_Q.json',
         'schemes/2x2x3_m11_foo_Z.json', 'schemes/2x3x3_m15_ZT.json', 'schemes/bad_name.json', 'top_2x2x2_m6_Q.json',
         'known/3x5x5_m70_Z.json', 'schemes/4x3x3_m44_Z.json']
for name in names:
    write('extra/' + name, '{}\n')

# witnesses
write('witnesses/seeds/matmul_2x2_rank7.txt', decimal(strassen, prefix='R '))
write('witnesses/checkpoints/2x2x2/best.txt', decimal(strassen, header=True))
write('witnesses/mfw/strassen.mfw', blob((2, 2, 2), strassen))
write('witnesses/gz/strassen.mfw.gz.b64',
      base64.encodebytes(gzip.compress(blob((2, 2, 2), strassen), mtime=0)))
write('witnesses/naive/matmul_2x2_rank8_gf2.txt', decimal(naive((2, 2, 2)), prefix='R '))
write('witnesses/bad/2x2x2/best.txt', decimal(flipped, header=True))
write('witnesses/rect/2x3x3/best.txt', decimal(naive((3, 3, 2)), header=True))
write('witnesses/rect/matmul_3x4_naive_gf2.txt', decimal(naive((3, 4, 3)), prefix='R '))
write('witnesses/rect/334.mfw', blob((3, 3, 4), naive((3, 3, 4))))
write('witnesses/rect/matmul_3x5_naive_gf2.txt', decimal(naive((3, 5, 3)), prefix='R '))
write('witnesses/unsorted/2x2x2.mfw', blob((2, 2, 2), strassen[::-1], order=False))
write('witnesses/.hidden/2x2x2/best.txt', decimal(strassen, header=True))
write('witnesses/ignored/notes.txt', 'not a witness\n')
write('witnesses/noshape/best.txt', decimal(strassen, header=True))
write('witnesses/mixed/3x4x4/best.txt', decimal(naive((4, 3, 4)), header=True))
write('witnesses/short/2x2x2/best.txt', '7\n1 2\n')

# name parsing
cases = ['2x2x2', 'matmul_3x4_rank36', 'a12x34x56b', 'x1y2x3', '5x', 'x5', '12x3x', '7x8x9x10', '1x2xx3', 'abc', '33x2_3x4x5',
         'best.txt', '2x3x4-note', '100x200x300_m5']
ring_names = names + ['3x3x3_m23_ZT_Z.json', '3x3x3_m23_a_b_ZT.json', '3x3x3_m23a_ZT.json', '3x3x3_m_ZT.json', 'x3x3x3_m23_Q.json',
                      'dir/4x4x4_m47_ZT.json', '4x4x4_m47_ZT.jsonx', '4x4x4_m47_QT.json', '10x3x7_m99_Q.json', 'a/b/5x6x7_m80__Q.json']
with (OUT / 'dims.tsv').open('w') as out:
    for name in cases:
        match = re.search(r'(\d+)x(\d+)(?:x(\d+))?', name)
        found = [int(g) for g in match.groups() if g] if match else None
        out.write(f'{name}\t{json.dumps(found)}\n')
with (OUT / 'ring.tsv').open('w') as out:
    for name in ring_names:
        match = grb.RING.search(name)
        if match and '/known/' not in name:
            key = 'x'.join(map(str, sorted(map(int, match.group(1, 2, 3)))))
            out.write(f'{name}\t{key}\t{match.group(5)}\t{int(match.group(4))}\n')
        else:
            out.write(f'{name}\tNone\n')
(OUT / 'fmm_ranks.json').write_text(json.dumps(
    {'x'.join(map(str, key)): rings for key, rings in grb.fmm_ranks(ring_names).items()}, indent=1, sort_keys=True) + '\n')
with (OUT / 'decode.tsv').open('w') as out:
    for path in sorted(p for p in IN.rglob('*') if p.is_file() and 'extra' not in p.parts and p.suffix != '.json'):
        raw = grb.load(path)
        try:
            shape, terms = grb.decode(path, raw)
            verdict = json.dumps([list(shape), len(terms)])
        except (AssertionError, ValueError, IndexError):
            verdict = 'None'
        out.write(f'{path.relative_to(IN)}\t{verdict}\n')

# the whole tool
cache = HERE / 'cache.tmp.json'
cache.unlink(missing_ok=True)
run = subprocess.run([sys.executable, str(TOOLS / 'gf2_record_board.py'), '--lille', str(IN / 'lille.json'),
                      '--matmulcatalog', str(IN / 'catalog.json'), '--extra-repo', str(IN / 'extra'),
                      '--witness', str(IN / 'witnesses'), '--jobs', '1', '--cache', str(cache),
                      '--json', str(OUT / 'rows.raw'), '-v'], capture_output=True, text=True, check=True)
fix = str(IN)
(OUT / 'rows.json').write_text((OUT / 'rows.raw').read_text().replace(fix, '@FIX@'))
(OUT / 'rows.raw').unlink()
(OUT / 'cache.json').write_text(cache.read_text() + '\n')
cache.unlink()
lines = run.stdout.replace(fix, '@FIX@').splitlines()
(OUT / 'summary.txt').write_text(lines[0] + '\n')
(OUT / 'verbose.txt').write_text('\n'.join(lines[1:]) + '\n')
(OUT / 'stderr.txt').write_text(run.stderr.replace(fix, '@FIX@'))
print(run.stdout)
print(run.stderr)
