#!/usr/bin/env python3
"""Regenerates spec/fixtures/gf2_catalogue_seeds/ from the ORIGINAL driver (tools/mmc_gf2_seeds.py, the oracle).

  generate.py

writes, next to this file:

  tree/...                  a small synthetic matmulcatalog checkout: atoms in the dense and the sparse row-map layout (a
                            Strassen scheme, a Hopcroft-Kerr-shaped <2,2,3>, a naive <3,3,3>, a rational-only and an
                            integer-only one), recipes that succeed, one that claims one product too few, recipes that need a
                            leaf the F2 atoms do not have (a local witness, an integer-only atom), a recipe over an atom with an
                            even denominator, one over a leaf that is no reference, and entries `targets` must skip
                            (commutative, complex, not F2, a dimension of 1, a dimension above 32)
  in/                       the inputs of the cases: listed ranks (lille.json, one entry listed unsorted), an extra repository of
                            file names, a scoreboard with witnesses (board.json: `$WITNESS` stands for the witness directory),
                            the targets of a full run
  cases.json                the steps of the cases: {"name", "args"}; `{clone}`, `{cache}`, `{in}` and `{t}` stand for the
                            catalogue checkout, the shared cache directory, in/ and the scratch directory
  expected/revision.txt     the commit hash of the tree (the test commits the same tree with the same author and date)
  expected/<step>/stdout.txt    what the step prints, scratch paths written `$T`
  expected/<step>/targets.json  (targets steps) the targets file
  expected/<step>/results.jsonl, seeds.json, files.txt   (replay steps) the log with `secs` zeroed, the seed list and the sorted
                            `name sha256` of every seed file
Everything here is derived from the Python original, never from the Tungsten port. Each step runs the original in a process of its
own: its replayer lives in module state, so one process keeps the board and ring options of the first command.
"""
import hashlib
import json
import os
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
import screen_top_two_projection_children as top  # noqa: E402

TREE = HERE / 'tree'
IN = HERE / 'in'
EXPECTED = HERE / 'expected'
PREFIX = 'src/main/resources/schemes/'
LADERMAN = BIT / 'lib/metaflip/seeds/gf2/matmul_3x3_rank23_d139_gf2.txt'
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
HK = G.concat_cols(STRASSEN, G.naive(2, 2, 1))                 # <2,2,3>, rank 11
assert HK.shape == (2, 2, 3) and G.check_exact(HK)
INTEGER = G.concat_cols(G.transpose(G.cyclic_shift(HK)), G.naive(2, 3, 1))   # <2,3,3>, rank 17 (the naive one has 18)
assert INTEGER.shape == (2, 3, 3) and INTEGER.r == 17 and G.check_exact(INTEGER)
NAIVE333 = G.naive(3, 3, 3)


def laderman():
    lines = LADERMAN.read_text().split()
    count, rows = int(lines[0]), [int(x) for x in lines[1:]]
    terms = [tuple(rows[3 * i:3 * i + 3]) for i in range(count)]
    alg = G.Alg(3, 3, 3, terms)
    assert count == 23 and G.check_exact(alg)
    return alg


LADERMAN_ALG = laderman()


def bits_of(mask, width):
    return [i for i in range(width) if (mask >> i) & 1]


def dense_atom(alg, odd=1, first=None):
    """u and v dense, w dense and column-major (the public layout); every set bit carries the coefficient `odd`."""
    n, mm, p = alg.shape
    u, v, w = [], [], []
    for t in alg.terms:
        ur = [0] * (n * mm)
        for i in bits_of(t[0], n * mm):
            ur[i] = odd
        vr = [0] * (mm * p)
        for i in bits_of(t[1], mm * p):
            vr[i] = odd
        wr = [0] * (n * p)
        for q in bits_of(t[2], n * p):
            i, j = divmod(q, p)
            wr[j * n + i] = odd
        u.append(ur), v.append(vr), w.append(wr)
    if first is not None:
        u[0][bits_of(alg.terms[0][0], n * mm)[0]] = first
    return dict(n=list(alg.shape), m=alg.r, z2=False, u=u, v=v, w=w)


def rowmap_atom(alg):
    n, mm, p = alg.shape

    def rows(masks, width, wcol=False):
        out = []
        for mask in masks:
            entries = {}
            for q in bits_of(mask, width):
                pos = q
                if wcol:
                    i, j = divmod(q, p)
                    pos = j * n + i
                entries[str(pos)] = 1
            out.append(entries)
        return {str(k): dict(i=[int(x) for x in e], c=list(e.values())) for k, e in enumerate(out)}
    return dict(n=list(alg.shape), m=alg.r, u_sparse=rows([t[0] for t in alg.terms], n * mm),
                v_sparse=rows([t[1] for t in alg.terms], mm * p), w_sparse=rows([t[2] for t in alg.terms], n * p, True))


FILES = {}
CATALOG = []


def add(path, doc, shape, rank, fields, **extra):
    if doc is not None:
        FILES[path] = doc
    CATALOG.append(dict(format=list(shape), rank=rank, fields=fields, file=path, **extra))


def atom(stem):
    return dict(op='Atom', ref=stem)


STRASSEN_FILE = 'known/s2/2x2x2-r7-strassen-abcdef0.json'
HK_FILE = 'known/s2/2x2x3-r11-hk-2222222.json'
NAIVE_FILE = 'known/s2/3x3x3-r27-naive-9999999.json'
RATIONAL_FILE = 'known/s2/2x2x2-r7-rational-4444444.json'
INTEGER_FILE = 'known/s2/2x3x3-r17-integer-aaaaaaa.json'
KRON_FILE = 'derived/s4/4x4x4-r49-derived-1111111.json'
OVER_FILE = 'derived/s4/4x4x4-r48-derived-2222222.json'
CONCAT_FILE = 'derived/s4/2x2x5-r18-derived-3333333.json'
BOARD_FILE = 'derived/s4/6x6x6-r161-derived-4444444.json'
WIDE_FILE = 'derived/s4/4x6x6-r119-derived-5555555.json'
QUARTER_FILE = 'derived/s4/2x2x4-r14-derived-6666666.json'
NOLEAF_FILE = 'derived/s4/3x3x5-r40-derived-7777777.json'

add(STRASSEN_FILE, dense_atom(STRASSEN), (2, 2, 2), 7, ['F2', 'Z', 'Q'], atom=True, source='Strassen 1969', year=1969,
    source_paper_url='https://example.invalid/strassen', source_scheme_url='https://example.invalid/strassen.json')
add(HK_FILE, rowmap_atom(HK), (2, 2, 3), 11, ['F2', 'Z'], atom=True, source='Hopcroft-Kerr 1971', year=1971)
add(NAIVE_FILE, dense_atom(NAIVE333), (3, 3, 3), 27, ['F2'], atom=True, source='definition')
add(RATIONAL_FILE, dense_atom(STRASSEN, first='1/2'), (2, 2, 2), 7, ['Q'], atom=True, source='rational')
add(INTEGER_FILE, dense_atom(INTEGER, odd=3), (2, 3, 3), 17, ['Z'], atom=True, source='an integer scheme', year=2022)
add('known/s2/2x2x2-r7-commutative-8888888.json', dense_atom(STRASSEN), (2, 2, 2), 7, ['F2'], atom=True, commutative=True)
add('known/s2/2x2x2-r5-complex-9999990.json', dense_atom(STRASSEN), (2, 2, 2), 5, ['F2'], atom=True, complex=True)
KRON = dict(op='KronProduct', outer=atom('2x2x2-r7-strassen-abcdef0'), inner=atom('2x2x2-r7-strassen-abcdef0'))
add(KRON_FILE, dict(n=[4, 4, 4], m=49, lineage=KRON), (4, 4, 4), 49, ['F2', 'Z'], lineage_compact='2x2x2 kron 2x2x2')
add(OVER_FILE, dict(n=[4, 4, 4], m=48, lineage=KRON), (4, 4, 4), 48, ['F2'], lineage_compact='claims 48')
add(CONCAT_FILE, dict(n=[2, 2, 5], m=18, lineage=dict(op='ConcatCols', left=atom('2x2x2-r7-strassen-abcdef0'),
                                                      right=atom('2x2x3-r11-hk-2222222'))),
    (2, 2, 5), 18, ['F2', 'Z'], lineage_compact='2x2x2 | 2x2x3')
add(BOARD_FILE, dict(n=[6, 6, 6], m=161, lineage=dict(op='KronProduct', outer=atom('2x2x2-r7-strassen-abcdef0'), inner=atom('3x3x3'))),
    (6, 6, 6), 161, ['F2'], lineage_compact='2x2x2 kron the rank-23 <3,3,3>')
add(WIDE_FILE, dict(n=[4, 6, 6], m=119, lineage=dict(op='KronProduct', outer=atom('2x2x2-r7-strassen-abcdef0'), inner=atom('2x3x3'))),
    (4, 6, 6), 119, ['F2'], lineage_compact='2x2x2 kron the rank-17 <2,3,3>')
add(QUARTER_FILE, dict(n=[2, 2, 4], m=14, lineage=atom('2x2x2-r7-rational-4444444')), (2, 2, 4), 14, ['F2'])
add(NOLEAF_FILE, dict(n=[3, 3, 5], m=40, lineage=atom('no such leaf')), (3, 3, 5), 40, ['F2'])
add('derived/s4/1x4x4-r16-derived-8888880.json', None, (1, 4, 4), 16, ['F2'])
add('derived/s4/2x2x40-r100-derived-8888881.json', None, (2, 2, 40), 100, ['F2'])
add('derived/s4/2x2x2-r7-derived-8888882.json', None, (2, 2, 2), 7, [])

TARGETS_ALL = [dict(mmc_file=f, canonical=c, mmc_rank=r) for f, c, r in [
    (KRON_FILE, '4x4x4', 49), (OVER_FILE, '4x4x4', 48), (CONCAT_FILE, '2x2x5', 18), (BOARD_FILE, '6x6x6', 161),
    (WIDE_FILE, '4x6x6', 119), (QUARTER_FILE, '2x2x4', 14), (NOLEAF_FILE, '3x3x5', 40), (STRASSEN_FILE, '2x2x2', 7),
    (HK_FILE, '2x2x3', 11), (NAIVE_FILE, '3x3x3', 27)]]
LILLE = dict(entries=[dict(format=f, rank=r) for f, r in [
    ([2, 2, 2], 7), ([2, 2, 3], 11), ([3, 3, 3], 23), ([4, 4, 4], 49), ([2, 2, 5], 18), ([3, 3, 5], 40), ([6, 4, 6], 120),
    ([6, 6, 6], 162), ([2, 2, 4], 14), ([2, 3, 3], 15)]])
BOARD = [dict(shape='2x2x2', rank=7, kind='tie', path='$WITNESS/222.mfw'),
         dict(shape='3x3x3', rank=23, kind='tie', path='$WITNESS/333.mfw'),
         dict(shape='2x2x4', rank=14, kind='tie', path='$WITNESS/missing.mfw')]

COMMON = ['--clone', '{clone}', '--cache-dir', '{cache}']
STEPS = [
    ('targets', ['targets'] + COMMON + ['--lille', '{in}/lille.json', '--extra-repo', '{in}/extra', '--board', '{t}/board.json',
                                        '--out', '{t}/targets.json']),
    ('targets-slack', ['targets'] + COMMON + ['--lille', '{in}/lille.json', '--extra-repo', '{in}/extra', '--board', '{t}/board.json',
                                              '--slack', '1', '--out', '{t}/targets-slack.json']),
    ('targets-min-dim', ['targets'] + COMMON + ['--lille', '{in}/lille.json', '--extra-repo', '{in}/extra', '--board',
                                                '{t}/board.json', '--slack', '100', '--min-dim', '3', '--out',
                                                '{t}/targets-min-dim.json']),
    ('replay-plain', ['replay'] + COMMON + ['--targets', '{in}/targets-all.json', '--out', '{t}/out/plain']),
    ('replay-again', ['replay'] + COMMON + ['--targets', '{in}/targets-all.json', '--out', '{t}/out/plain']),
    ('replay-board', ['replay'] + COMMON + ['--targets', '{in}/targets-all.json', '--board', '{t}/board.json',
                                            '--out', '{t}/out/board']),
    ('replay-wide', ['replay'] + COMMON + ['--targets', '{in}/targets-all.json', '--allow-nonf2', '--out', '{t}/out/wide']),
    ('replay-retry', ['replay'] + COMMON + ['--targets', '{in}/targets-all.json', '--board', '{t}/board.json',
                                            '--retry-failed', '--out', '{t}/out/plain']),
    ('replay-only', ['replay'] + COMMON + ['--targets', '{in}/targets-all.json', '--only', '4x4x4', '2x2x5', HK_FILE,
                                           '--out', '{t}/out/only']),
    ('replay-selected', ['replay'] + COMMON + ['--targets', '{t}/targets.json', '--board', '{t}/board.json', '--allow-nonf2',
                                               '--out', '{t}/out/selected']),
]


def write_inputs():
    if TREE.exists():
        shutil.rmtree(TREE)
    for path, doc in FILES.items():
        target = TREE / PREFIX / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(doc, separators=(',', ':')) + '\n')
    (TREE / 'docs').mkdir(parents=True, exist_ok=True)
    (TREE / 'docs/catalog.json').write_text(json.dumps(dict(total=len(CATALOG), schemes=CATALOG), separators=(',', ':')) + '\n')
    if IN.exists():
        shutil.rmtree(IN)
    (IN / 'extra/schemes').mkdir(parents=True)
    (IN / 'extra/schemes/2x2x5_m17_ZT.json').write_text('{}\n')
    (IN / 'witnesses').mkdir()
    for name, alg in (('222.mfw', STRASSEN), ('333.mfw', LADERMAN_ALG)):
        (IN / 'witnesses' / name).write_bytes(top.blob(alg.shape, sorted(alg.terms)))
    (IN / 'lille.json').write_text(json.dumps(LILLE, indent=1) + '\n')
    (IN / 'board.json').write_text(json.dumps(BOARD, indent=1) + '\n')
    (IN / 'targets-all.json').write_text(json.dumps(TARGETS_ALL, indent=1) + '\n')
    (HERE / 'cases.json').write_text(json.dumps([dict(name=name, args=args) for name, args in STEPS], indent=1) + '\n')


def git(repo, *args):
    return subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True, text=True,
                          env={**os.environ, **GIT_ENV}).stdout


def normalized_results(text, scratch):
    rows = []
    for line in text.splitlines():
        row = json.loads(line)
        row['secs'] = 0
        rows.append(json.dumps(row))
    return ''.join(row + '\n' for row in rows).replace(scratch, '$T')


def main():
    write_inputs()
    if EXPECTED.exists():
        shutil.rmtree(EXPECTED)
    EXPECTED.mkdir()
    work = Path(tempfile.mkdtemp(prefix='gf2-seeds-'))
    scratch = str(work)
    try:
        repo = work / 'repo'
        shutil.copytree(TREE, repo)
        git(repo, 'init', '-q')
        git(repo, 'add', '-f', '.')
        git(repo, 'commit', '-q', '-m', 'fixture')
        (EXPECTED / 'revision.txt').write_text(git(repo, 'rev-parse', 'HEAD'))
        shutil.copytree(IN / 'witnesses', work / 'witnesses')
        (work / 'board.json').write_text((IN / 'board.json').read_text().replace('$WITNESS', str(work / 'witnesses')))
        for name, args in STEPS:
            expanded = [a.replace('{clone}', str(repo)).replace('{cache}', str(work / 'cache')).replace('{in}', str(IN))
                        .replace('{t}', scratch) for a in args]
            run = subprocess.run([sys.executable, str(BIT / 'tools/mmc_gf2_seeds.py'), *expanded], capture_output=True, text=True,
                                 cwd=scratch, env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})
            assert run.returncode == 0 and run.stderr == '', (name, run.returncode, run.stderr)
            target = EXPECTED / name
            target.mkdir()
            (target / 'stdout.txt').write_text(run.stdout.replace(scratch, '$T'))
            out = Path(expanded[expanded.index('--out') + 1])
            if args[0] == 'targets':
                (target / 'targets.json').write_text(out.read_text())
            else:
                (target / 'results.jsonl').write_text(normalized_results((out / 'results.jsonl').read_text(), scratch))
                (target / 'seeds.json').write_text((out / 'seeds.json').read_text().replace(scratch, '$T'))
                (target / 'files.txt').write_text(''.join(
                    f'{p.name} {hashlib.sha256(p.read_bytes()).hexdigest()}\n' for p in sorted(out.glob('*.mfw'))))
    finally:
        shutil.rmtree(work)
    print('wrote', len(FILES), 'files and', len(STEPS), 'steps')


if __name__ == '__main__':
    main()
