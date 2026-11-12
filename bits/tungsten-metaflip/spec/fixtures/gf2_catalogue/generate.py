#!/usr/bin/env python3
"""Regenerates spec/fixtures/gf2_catalogue/ from the ORIGINAL replay (tools/mmc_gf2_replay.py, the oracle).

  generate.py

writes, next to this file:

  tree/...           a synthetic matmulcatalog checkout: atoms in the dense, sparse, row-map and reduced layouts with integer,
                     rational, float and text coefficients, recipes (derived files) that use every operation of the lineage
                     language, every kind of leaf reference, and files that must fail (an inexact atom, an even denominator, a
                     cycle, a dangling @ref, a missing key, an unsupported operation, a shape that is not the declared one)
  expected/files.tsv      per catalogue file: `ok`, the shape, the rank and the SHA-256 of the sorted terms of the replay and its
                          dependencies as JSON, or `error` and the message of the ReplayError
  expected/best.tsv       candidates(key), best_rank and best(shape) for several shapes
  expected/parity.tsv     parity() of a list of coefficients (JSON), `ok 0|1` or `error` and the message
  expected/revision.txt   the commit hash of the tree (the test commits the same tree with the same author and date)
Everything here is derived from the Python original, never from the Tungsten port.
"""
import copy
import hashlib
import json
import os
import random
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
BIT = HERE.parents[2]
sys.path[:0] = [str(BIT / 'tools'), str(BIT / 'spec')]
os.environ.setdefault('PYTHONDONTWRITEBYTECODE', '1')
import mmc_gf2_alg as G  # noqa: E402
import mmc_gf2_replay as MR  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402

TREE = HERE / 'tree'
EXPECTED = HERE / 'expected'
PREFIX = 'src/main/resources/schemes/'
GIT_ENV = {'GIT_AUTHOR_NAME': 'fixture', 'GIT_AUTHOR_EMAIL': 'fixture@example.invalid',
           'GIT_COMMITTER_NAME': 'fixture', 'GIT_COMMITTER_EMAIL': 'fixture@example.invalid',
           'GIT_AUTHOR_DATE': '2026-09-30T12:00:00+0000', 'GIT_COMMITTER_DATE': '2026-09-30T12:00:00+0000',
           'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_CONFIG_SYSTEM': '/dev/null'}


def m(*idx):
    return sum(1 << i for i in idx)


STRASSEN = G.Alg(2, 2, 2, [
    (m(0, 3), m(0, 3), m(0, 3)), (m(2, 3), m(0), m(2, 3)), (m(0), m(1, 3), m(1, 3)),
    (m(3), m(0, 2), m(0, 2)), (m(0, 1), m(3), m(0, 1)), (m(0, 2), m(0, 1), m(3)),
    (m(1, 3), m(2, 3), m(0)),
])
assert G.check_exact(STRASSEN)
HK = G.concat_cols(STRASSEN, G.naive(2, 2, 1))          # <2,2,3> of rank 11
assert HK.shape == (2, 2, 3) and G.check_exact(HK)
rng = random.Random(7)
ODD = [1, -1, 3, '1', '-1', '5/1', '1/3', '-3/5', -0.3333333333333333, 1.0, 3.0, ' 7 ', '+1', '1e0']
EVEN = [2, -2, 4, '2', '6/3', 2.0, '0.0', 0, '0', '4e0']


def odd():
    return rng.choice(ODD)


def terms_bits(mask, width):
    return [i for i in range(width) if (mask >> i) & 1]


def dense_atom(alg, noisy=True):
    """u and v dense, w dense and column-major (the public layout)."""
    n, mm, p = alg.shape
    u, v, w = [], [], []
    for t in alg.terms:
        ur = [0] * (n * mm)
        for i in terms_bits(t[0], n * mm):
            ur[i] = odd() if noisy else 1
        vr = [0] * (mm * p)
        for i in terms_bits(t[1], mm * p):
            vr[i] = odd() if noisy else 1
        wr = [0] * (n * p)
        for q in terms_bits(t[2], n * p):
            i, j = divmod(q, p)
            wr[j * n + i] = odd() if noisy else 1
        if noisy:
            for row in (ur, vr, wr):
                for _ in range(2):
                    k = rng.randrange(len(row))
                    if row[k] == 0:
                        row[k] = rng.choice(EVEN)
        u.append(ur), v.append(vr), w.append(wr)
    return dict(n=list(alg.shape), m=alg.r, z2=False, u=u, v=v, w=w)


def sparse_atom(alg, rowmap=False):
    n, mm, p = alg.shape

    def rows(masks, width, wcol=False):
        out = []
        for mask in masks:
            entries = {}
            for q in terms_bits(mask, width):
                pos = q
                if wcol:
                    i, j = divmod(q, p)
                    pos = j * n + i
                entries[str(pos)] = odd()
            for _ in range(2):
                pos = rng.randrange(width)
                if str(pos) not in entries:
                    entries[str(pos)] = rng.choice(EVEN)
            out.append(entries)
        return out
    us, vs, ws = rows([t[0] for t in alg.terms], n * mm), rows([t[1] for t in alg.terms], mm * p), \
        rows([t[2] for t in alg.terms], n * p, True)
    if rowmap:
        def conv(rows_):
            return {str(k): dict(i=[int(x) for x in e], c=list(e.values())) for k, e in enumerate(rows_)}
        us, vs, ws = conv(us), conv(vs), conv(ws)
    return dict(n=list(alg.shape), m=alg.r, u_sparse=us, v_sparse=vs, w_sparse=ws)


def reduced_atom(alg):
    n, mm, p = alg.shape
    u = [[dict(index=i, value=odd()) for i in terms_bits(t[0], n * mm)] for t in alg.terms]
    v = [[dict(index=i, value=odd()) for i in terms_bits(t[1], mm * p)] for t in alg.terms]
    w = [[] for _ in range(n * p)]
    for k, t in enumerate(alg.terms):
        for q in terms_bits(t[2], n * p):
            i, j = divmod(q, p)
            w[j * n + i].append(dict(index=k, value=odd()))
    return dict(n=list(alg.shape), m=alg.r, u=u, v=v, w=w)


FILES = {}
CATALOG = []


def add(path, doc, shape, rank, fields, atom=False, **extra):
    FILES[path] = doc
    entry = dict(format=list(shape), rank=rank, fields=fields, file=path, atom=atom, **extra)
    CATALOG.append(entry)


def ref(stem):
    return dict(op='Atom', ref=stem)


A_STRASSEN = 'known/s2/2x2x2-r7-strassen-abcdef0.json'
A_NAIVE222 = 'known/s2/2x2x2-r8-naive-1111111.json'
A_HK = 'known/s2/2x2x3-r11-hk-2222222.json'
A_REDUCED = 'known/s2/2x2x2-r8-reduced-3333333.json'
A_QONLY = 'known/s2/2x2x2-r7-rational-4444444.json'
A_BROKEN = 'known/s2/2x2x2-r7-broken-5555555.json'
A_HK_DENSE = 'known/s2/2x3x2-r11-hkdense-6666666.json'

add(A_STRASSEN, dense_atom(STRASSEN), (2, 2, 2), 7, ['F2', 'Z', 'Q'], atom=True, source='Strassen 1969', year=1969)
add(A_NAIVE222, sparse_atom(G.naive(2, 2, 2)), (2, 2, 2), 8, ['F2', 'Z', 'Q'], atom=True, source='definition')
add(A_HK, sparse_atom(HK, rowmap=True), (2, 2, 3), 11, ['F2', 'Z'], atom=True, source='Hopcroft-Kerr 1971', year=1971)
add(A_REDUCED, reduced_atom(G.naive(2, 2, 2)), (2, 2, 2), 8, ['F2'], atom=True)
q = dense_atom(STRASSEN, noisy=False)
q['u'][0][0] = '1/2'
add(A_QONLY, q, (2, 2, 2), 7, ['Q'], atom=True, source='rational')
b = dense_atom(STRASSEN, noisy=False)
b['w'][3][0] = 1 - b['w'][3][0]
add(A_BROKEN, b, (2, 2, 2), 7, ['F2'], atom=True)
add(A_HK_DENSE, dense_atom(G.transpose(G.cyclic_shift(HK))), (2, 3, 2), 11, ['F2'], atom=True, source='the same, oriented')
# a commutative entry and a complex one: neither is a candidate
add('known/s2/2x2x2-r7-commutative-7777777.json', dense_atom(STRASSEN), (2, 2, 2), 7, ['F2'], atom=True, commutative=True)
add('known/s2/2x2x2-r5-complex-8888888.json', dense_atom(STRASSEN), (2, 2, 2), 5, ['F2'], atom=True, complex=True)

S, H, N = 'Strassen', 'HK', 'N'
recipes = {
    'derived/s4/4x4x4-r49-derived-aaaaaaa.json': (
        (4, 4, 4), 49, dict(op='KronProduct', outer=ref('2x2x2-r7-strassen-abcdef0'), inner=ref('2x2x2-r7-strassen-abcdef0'))),
    'derived/s4/2x2x5-r18-derived-bbbbbbb.json': (
        (2, 2, 5), 18, dict(op='ConcatCols', left=ref('2x2x2-r7-strassen-abcdef0'), right=ref('2x2x3-r11-hk-2222222'))),
    'derived/s4/4x2x2-r14-derived-ccccccc.json': (
        (4, 2, 2), 14, dict(op='ConcatRows', top=ref('2x2x2-r7-strassen-abcdef0'), bottom=ref('2x2x2-r7-strassen-abcdef0'))),
    'derived/s4/2x4x2-r14-derived-ddddddd.json': (
        (2, 4, 2), 14, dict(op='SumInner', left=ref('2x2x2-r7-strassen-abcdef0'), right=ref('2x2x2-r7-strassen-abcdef0'))),
    'derived/s4/3x2x2-r11-derived-eeeeeee.json': (
        (3, 2, 2), 11, dict(op='Transpose', child=ref('2x2x3-r11-hk-2222222'), perm='ABC->CBA')),
    'derived/s4/3x2x2-r11-derived-fffffff.json': (
        (3, 2, 2), 11, dict(op='Transpose', child=ref('2x2x3-r11-hk-2222222'), perm='NMP->PMN')),
    'derived/s4/2x3x2-r11-derived-0000001.json': (
        (2, 3, 2), 11, dict(op='Transpose', child=ref('2x2x3-r11-hk-2222222'), perm='ABC->XYZ')),
    'derived/s4/3x2x2-r11-derived-0000002.json': (
        (3, 2, 2), 11, dict(op='Transpose', child=ref('2x2x3-r11-hk-2222222'), perm='ABC->CAB')),
    'derived/s4/2x3x2-r11-derived-0000003.json': (
        (2, 3, 2), 11, dict(op='OrientAs', child=ref('2x2x3-r11-hk-2222222'), n=2, m=3, p=2)),
    'derived/s4/2x3x2-r11-derived-0000004.json': (
        (3, 2, 2), 11, dict(op='OrientAs', child=ref('2x2x3-r11-hk-2222222'), axisMap='pmn')),
    'derived/s4/2x3x2-r11-derived-0000005.json': (
        (2, 2, 3), 11, dict(op='OrientAs', child=ref('2x2x3-r11-hk-2222222'), n=5, m=5, p=5)),
    'derived/s4/2x2x3-r11-derived-0000006.json': (
        (2, 2, 3), 11, dict(op='AxisPermute', child=ref('2x2x3-r11-hk-2222222'), permA=[1, 0], permB=[0, 1], permC=[2, 0, 1])),
    'derived/s4/2x2x3-r11-derived-0000007.json': (
        (2, 2, 3), 11, dict(op='DCE', child=ref('2x2x3-r11-hk-2222222'))),
    'derived/s4/2x2x2-r7-derived-0000008.json': (
        (2, 2, 2), 7, dict(op='Project', child=ref('2x2x3-r11-hk-2222222'), keepN=[0, 1], keepM=[0, 1], keepP=[0, 2])),
    'derived/s4/4x4x4-r49-derived-0000009.json': (
        (4, 4, 4), 49, dict(op='KronChain', factors=[ref('2x2x2-r7-strassen-abcdef0'), ref('naive-1x1x1'), ref('2x2x2-r7-strassen-abcdef0')])),
    'derived/s4/4x4x4-r49-derived-000000a.json': (
        (4, 4, 4), 49, dict(op='KronProduct', outer=dict(id='shared', op='Atom', ref='2x2x2-r7-strassen-abcdef0'), inner=dict(op='@ref', id='shared'))),
    'derived/s4/6x4x4-r98-derived-000000b.json': (
        (4, 4, 6), 49, dict(op='SerendipitousProduct', base=ref('2x2x2-r7-strassen-abcdef0'), n2=2, m2=2, p2=3)),
    'derived/s4/4x4x4-r49-derived-000000c.json': (
        (4, 4, 4), 49, dict(op='SerendipitousProduct', base=ref('2x2x2-r7-strassen-abcdef0'), n2=2, m2=2, p2=2)),
    'derived/s4/6x3x4-r80-derived-000000d.json': (
        (6, 3, 4), 80, dict(op='Recombination', base=ref('2x2x2-r7-strassen-abcdef0'), allocA=[3, 3], allocB=[1, 2], allocC=[2, 2])),
    'derived/s4/5x2x3-r70-derived-000000e.json': (
        (5, 2, 3), 70, dict(op='RecombinationN', base=ref('2x2x2-r7-strassen-abcdef0'), allocA=[3, 2], allocB=[1, 1], allocC=[1, 2],
                            leaves=[ref('2x2x3-r11-hk-2222222'), ref('2x2x2-r8-naive-1111111')])),
    'derived/s4/2x2x2-r7-derived-000000f.json': (
        (2, 2, 2), 7, ref('2x2x2@abcdef0')),
    'derived/s4/3x2x2-r12-derived-0000010.json': (
        (3, 2, 2), 12, ref('naive-3x2x2')),
    'derived/s4/2x2x3-r11-derived-0000011.json': (
        (2, 2, 3), 11, ref('2x2x3')),
    'derived/s4/2x2x3-r11-derived-0000012.json': (
        (2, 2, 3), 11, ref('3x2x2@2222222')),
    'derived/s4/2x2x2-r7-derived-0000013.json': (
        (2, 2, 2), 7, ref('Strassen<2,2,2>=7')),
    'derived/s4/2x2x2-r8-derived-0000014.json': (
        (2, 2, 2), 8, ref('Naive<2,2,2>=8')),
    'derived/s4/2x2x3-r11-derived-0000015.json': (
        (2, 2, 3), 11, ref('ext[2x2x3-r11-hk-2222222.json]')),
    'derived/s4/3x2x2-r11-derived-0000016.json': (
        (3, 2, 2), 11, ref('ext[2x2x3-r11-hk-2222222] / <3,2,2>=11')),
    'derived/s4/2x2x2-r8-derived-0000017.json': (
        (2, 2, 2), 8, ref('2x2x2-r8-reduced-3333333')),
    'derived/s4/2x2x2-r7-derived-0000018.json': (
        (2, 2, 2), 7, ref('mystery <2, 2, 2> leaf')),
    'derived/s4/2x2x2-r7-derived-0000019.json': (
        (2, 2, 2), 7, ref('TA_sz(n=4)')),
    'derived/s4/2x2x2-r7-derived-000001a.json': (
        (2, 2, 2), 7, ref('no such leaf')),
    'derived/s4/2x2x2-r7-derived-000001b.json': (
        (2, 2, 2), 7, ref('7x7x7@0000000')),
    'derived/s4/2x2x2-r7-derived-000001c.json': (
        (2, 2, 2), 7, ref('2x2x2-r7-rational-4444444')),
    'derived/s4/2x2x2-r7-derived-000001d.json': (
        (2, 2, 2), 7, ref('2x2x2-r7-broken-5555555')),
    'derived/s4/2x2x2-r7-derived-000001e.json': (
        (2, 2, 2), 7, dict(op='Frobnicate', child=ref('2x2x2-r7-strassen-abcdef0'))),
    'derived/s4/2x2x2-r7-derived-000001f.json': (
        (2, 2, 2), 7, dict(op='KronProduct', outer=ref('2x2x2-r7-strassen-abcdef0'))),
    'derived/s4/2x2x2-r7-derived-0000020.json': (
        (2, 2, 2), 7, dict(op='KronProduct', outer=dict(op='@ref', id='missing'), inner=ref('2x2x2-r7-strassen-abcdef0'))),
    'derived/s4/4x4x4-r49-derived-0000021.json': (
        (2, 2, 2), 49, dict(op='KronProduct', outer=ref('2x2x2-r7-strassen-abcdef0'), inner=ref('2x2x2-r7-strassen-abcdef0'))),
    'derived/s4/2x2x2-r7-derived-0000022.json': (
        (2, 2, 2), 7, dict(op='ConcatCols', left=ref('2x2x2-r7-strassen-abcdef0'), right=ref('2x2x3-r11-hk-2222222'))),
    'derived/s4/2x2x2-r7-derived-0000023.json': (
        (2, 2, 2), 7, dict(op='Recombination', base=ref('2x2x2-r7-strassen-abcdef0'), allocA=[1], allocB=[2, 2], allocC=[2, 2])),
}
for path, (shape, rank, lineage) in recipes.items():
    doc = dict(n=list(shape), m=rank, lineage=lineage)
    add(path, doc, shape, rank, ['F2', 'Z'], lineage_compact='synthetic')
# stubs without a lineage, a cycle and a stub of a stub
add('derived/s4/2x2x2-r7-derived-0000030.json', dict(n=[2, 2, 2], m=7), (2, 2, 2), 7, ['F2'])
add('derived/s4/2x2x2-r7-derived-0000031.json', dict(n=[2, 2, 2], m=7, lineage=ref('2x2x2-r7-derived-0000031')), (2, 2, 2), 7, ['F2'])
add('derived/s4/2x2x2-r7-derived-0000032.json', dict(n=[2, 2, 2], m=7, lineage=ref('2x2x2-r7-derived-0000033')), (2, 2, 2), 7, ['F2'])
add('derived/s4/2x2x2-r7-derived-0000033.json', dict(n=[2, 2, 2], m=7, lineage=ref('2x2x2-r7-derived-0000032')), (2, 2, 2), 7, ['F2'])
add('derived/s4/2x2x2-r7-derived-0000034.json', dict(n=[2, 2, 2], m=7, lineage=ref('2x2x2-r7-derived-000000f')), (2, 2, 2), 7, ['F2'])
add('derived/s4/2x2x2-r7-derived-0000035.json', dict(m=7, lineage=ref('2x2x2-r7-strassen-abcdef0')), (2, 2, 2), 7, ['F2'])
# files that the catalogue does not list as candidates for some shapes
add('known/s2/3x3x3-r27-naive-9999999.json', dense_atom(G.naive(3, 3, 3), noisy=False), (3, 3, 3), 27, ['F2'], atom=True)


def write_tree():
    if TREE.exists():
        shutil.rmtree(TREE)
    for path, doc in FILES.items():
        target = TREE / PREFIX / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(doc, separators=(',', ':')) + '\n')
    (TREE / 'docs').mkdir(parents=True, exist_ok=True)
    (TREE / 'docs/catalog.json').write_text(json.dumps(dict(total=len(CATALOG), schemes=CATALOG), separators=(',', ':')) + '\n')


def git(repo, *args):
    return subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True, text=True,
                          env={**os.environ, **GIT_ENV}).stdout


PARITY_VALUES = ['0', '1', '-1', '2', '3', '-4', '1180591620717411303425', 'true', 'false', 'null', '1.0', '2.0', '-3.0', '0.5',
                 '-0.3333333333333333', '0.1', '1e-12', '123456.789', '0.30000000000000004', '"1"', '"-3/5"', '"1/2"', '" 7 "',
                 '"2/4"', '"abc"', '""', '"1e3"', '"0.25"', '"0.2"', '"-0.5e1"', '"1/0"', '"3/"', '"+9"', '"12e-1"', '[1]', '{}']


def parity_table():
    lines = []
    for text in PARITY_VALUES:
        value = json.loads(text)
        try:
            outcome = f'ok {MR.parity(value)}'
        except MR.ReplayError as exc:
            outcome = f'error ReplayError: {exc}'
        except Exception as exc:  # noqa: BLE001 -- a ValueError of Fraction and the like
            outcome = f'error {type(exc).__name__}: {exc!r}'
        lines.append(f'{text}\t{outcome}')
    return '\n'.join(lines) + '\n'


def files_table(source):
    lines = []
    for path in sorted(FILES):
        for disk in (False, True):
            replayer = MR.Replayer(source, use_disk_cache=disk)
            try:
                a = replayer.materialize_file(path)
                blob = top.blob(a.shape, sorted(a.terms))
                deps = sorted(replayer.deps_file[path], key=json.dumps)
                outcome = f'ok {"x".join(map(str, a.shape))} r{a.r} {hashlib.sha256(blob).hexdigest()} {json.dumps([list(d) for d in deps])}'
            except MR.ReplayError as exc:
                outcome = f'error {exc}'
            except RuntimeError as exc:
                outcome = f'fetch {exc}'
            if disk:
                assert outcome == previous, (path, outcome, previous)
            previous = outcome
        lines.append(f'{path}\t{outcome}')
    return '\n'.join(lines) + '\n'


def best_table(source):
    rp = MR.Replayer(source, use_disk_cache=False)
    lines = []
    for key in ((2, 2, 2), (2, 2, 3), (2, 3, 3), (3, 3, 3), (1, 4, 4), (2, 2, 9), (4, 4, 4)):
        cands = [f'{e["rank"]}:{e["file"]}' for e in rp.candidates(key)]
        rank = rp.best_rank(key)
        a = rp.best(key)
        lines.append(f'{"x".join(map(str, key))}\t{json.dumps(cands)}\t{rank}\t{a.shape if a else None} r{a.r if a else None} '
                     f'{hashlib.sha256(top.blob(a.shape, sorted(a.terms))).hexdigest() if a else ""}')
    for shape in ((3, 2, 2), (2, 3, 2), (2, 2, 3)):
        a = MR.Replayer(source, use_disk_cache=False).best(shape)
        lines.append(f'oriented {"x".join(map(str, shape))}\t{a.shape} r{a.r} {hashlib.sha256(top.blob(a.shape, a.terms)).hexdigest()}')
    return '\n'.join(lines) + '\n'


def main():
    write_tree()
    if EXPECTED.exists():
        shutil.rmtree(EXPECTED)
    EXPECTED.mkdir()
    (EXPECTED / 'parity.tsv').write_text(parity_table())
    work = Path(tempfile.mkdtemp(prefix='gf2-catalogue-'))
    try:
        repo = work / 'repo'
        shutil.copytree(TREE, repo)
        git(repo, 'init', '-q')
        git(repo, 'add', '-f', '.')
        git(repo, 'commit', '-q', '-m', 'fixture')
        (EXPECTED / 'revision.txt').write_text(git(repo, 'rev-parse', 'HEAD'))
        source = MR.Source(repo, 'HEAD', work / 'cache')
        (EXPECTED / 'files.tsv').write_text(files_table(source))
        (EXPECTED / 'best.tsv').write_text(best_table(source))
    finally:
        shutil.rmtree(work)
    print('wrote', len(FILES), 'files')


if __name__ == '__main__':
    main()
