#!/usr/bin/env python3
"""Regenerates spec/fixtures/gf2_public_ternary/ from the ORIGINAL tool (tools/screen_public_ternary_gf2.py, the oracle).

  generate.py

writes, next to this file:

  tree/schemes/found/...   a small FastMatrixMultiplication-format scheme tree: the naive and Strassen schemes of several shapes with
                           integer, ternary and rational coefficients, and mutated copies the tool must reject or normalize (wrong
                           sizes, missing keys, non-integer coefficients, an inexact scheme, a rank that disagrees with the file name,
                           terms that cancel or vanish modulo two, broken JSON) and files it must skip (`known/`, `_Q` without the flag)
  walker_stub.sh           a stand-in for the compiled walker: prints the result line the tool parses, or fails, by the seed's name
  expected/parity.tsv      `value (JSON)`, TAB, `ok <0|1>` or `error <message>` of the original's parity()
  expected/parse_result.tsv  text (JSON string), TAB, the three numbers the RESULT pattern finds, or `none`
  expected/integer_files.json  integer_files() of the tree for four (alternatives, rational) pairs
  expected/runs/<name>/    seeds.json, summary.txt and mfw.tsv (file name, SHA-256) of `seeds` for several option sets
  expected/walk.tsv        the rows of `walk` with the stub, sorted

The tree is committed as one commit with fixed author, committer and date (the test builds the same commit, so its hash is the same).
Everything here is derived from the Python original, never from the Tungsten port.
"""
import hashlib
import io
import itertools
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from contextlib import redirect_stdout
from pathlib import Path

HERE = Path(__file__).resolve().parent
BIT = HERE.parents[2]
REPO = BIT.parents[1]
sys.path[:0] = [str(BIT / 'tools'), str(BIT / 'spec'), str(REPO / 'benchmarks/matmul/metaflip')]
os.environ.setdefault('PYTHONDONTWRITEBYTECODE', '1')
import screen_public_ternary_gf2 as tool  # noqa: E402

TREE = HERE / 'tree'
EXPECTED = HERE / 'expected'
URL = 'https://example.invalid/fixture-schemes'
GIT_ENV = {'GIT_AUTHOR_NAME': 'fixture', 'GIT_AUTHOR_EMAIL': 'fixture@example.invalid',
           'GIT_COMMITTER_NAME': 'fixture', 'GIT_COMMITTER_EMAIL': 'fixture@example.invalid',
           'GIT_AUTHOR_DATE': '2026-09-30T12:00:00+0000', 'GIT_COMMITTER_DATE': '2026-09-30T12:00:00+0000',
           'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_CONFIG_SYSTEM': '/dev/null'}


# ---- the schemes ---------------------------------------------------------------------------------

def naive(n, m, p):
    u, v, w = [], [], []
    for i, j, k in itertools.product(range(n), range(m), range(p)):
        u.append([1 if a == i * m + j else 0 for a in range(n * m)])
        v.append([1 if a == j * p + k else 0 for a in range(m * p)])
        w.append([1 if a == k * n + i else 0 for a in range(p * n)])  # the public W row is indexed C[k][i]
    return dict(n=[n, m, p], m=n * m * p, z2=False, u=u, v=v, w=w)


def strassen():
    # A = [[a11, a12], [a21, a22]] at i*2+j; B at j*2+k; C[k][i] at k*2+i
    def row(entries, width=4):
        r = [0] * width
        for index, coefficient in entries:
            r[index] = coefficient
        return r
    a11, a12, a21, a22 = 0, 1, 2, 3
    b11, b12, b21, b22 = 0, 1, 2, 3
    c11, c12, c21, c22 = 0, 2, 1, 3
    products = [
        ([(a11, 1), (a22, 1)], [(b11, 1), (b22, 1)], [(c11, 1), (c22, 1)]),
        ([(a21, 1), (a22, 1)], [(b11, 1)], [(c21, 1), (c22, -1)]),
        ([(a11, 1)], [(b12, 1), (b22, -1)], [(c12, 1), (c22, 1)]),
        ([(a22, 1)], [(b21, 1), (b11, -1)], [(c11, 1), (c21, 1)]),
        ([(a11, 1), (a12, 1)], [(b22, 1)], [(c11, -1), (c12, 1)]),
        ([(a21, 1), (a11, -1)], [(b11, 1), (b12, 1)], [(c22, 1)]),
        ([(a12, 1), (a22, -1)], [(b21, 1), (b22, 1)], [(c11, 1)]),
    ]
    return dict(n=[2, 2, 2], m=7, z2=False, u=[row(a) for a, _, _ in products], v=[row(b) for _, b, _ in products],
                w=[row(c) for _, _, c in products])


def copy_of(scheme):
    return json.loads(json.dumps(scheme))


def oddify(scheme, factor=3):
    """Same scheme modulo two: every odd coefficient becomes factor * coefficient (or its negative), every 0 an even number."""
    result = copy_of(scheme)
    for name in 'uvw':
        for row in result[name]:
            for i, value in enumerate(row):
                row[i] = value * factor if value else 2 * (i % 3) * (1 if i % 2 else -1)
    return result


def rational(scheme, odd=True):
    result = copy_of(scheme)
    for name in 'uvw':
        for row in result[name]:
            for i, value in enumerate(row):
                if value:
                    row[i] = f'{value * 3}/9' if odd and i % 2 else (f'{value * 5}/3' if odd else f'{value}/2')
    return result


FILES = {}


def put(path, value, raw=False):
    FILES['schemes/found/' + path] = value if raw else json.dumps(value, separators=(',', ':')) + '\n'


S = strassen()
put('ZT/2x2x2_m7_ZT.json', S)
put('Z/2x2x2_m7_Z.json', oddify(S))                       # the same GF(2) terms: a duplicate seed
put('ZT/2x2x2_m8_ZT.json', naive(2, 2, 2))                # best + 1
put('Q/2x2x2_m7_Q.json', rational(S))                     # odd denominators, equal terms again
put('Q/2x2x3_m11_Q.json', rational(naive(2, 2, 3), odd=False) | dict(m=12))  # even denominators (and the wrong rank: see below)
put('ZT/3x2x2_m12_ZT.json', naive(3, 2, 2))               # another orientation of 2x2x3
put('Z/2x2x3_m12_Z.json', naive(2, 2, 3))
put('ZT/2x2x9_m36_ZT.json', naive(2, 2, 9))               # too long for --max-dim 8
put('ZT/known/2x3x3_m18_ZT.json', naive(2, 3, 3))         # `known/` is skipped
put('serendipitous_base/2x3x3_m18_ab12_Q.json', naive(2, 3, 3))  # the ring is the suffix, not the directory
put('ZT/2x3x4_m24_ZT.json', naive(2, 3, 4))

bad = naive(2, 3, 3)
mutations = {
    'bad_size_u': lambda s: s | dict(u=s['u'][:-1]),
    'bad_size_row': lambda s: s | dict(v=[r[:-1] if i == 2 else r for i, r in enumerate(s['v'])]),
    'missing_w': lambda s: {k: v for k, v in s.items() if k != 'w'},
    'missing_n': lambda s: {k: v for k, v in s.items() if k != 'n'},
    'missing_m': lambda s: {k: v for k, v in s.items() if k != 'm'},
    'z2_true': lambda s: s | dict(z2=True),
    'z2_zero': lambda s: s | dict(z2=0),
    'z2_null': lambda s: s | dict(z2=None),
    'z2_absent': lambda s: {k: v for k, v in s.items() if k != 'z2'},
    'short_n': lambda s: s | dict(n=[2, 3]),
    'zero_dim': lambda s: s | dict(n=[2, 0, 3]),
    'float_coefficient': lambda s: s | dict(u=[[1.0] + r[1:] if i == 0 else r for i, r in enumerate(s['u'])]),
    'bool_coefficient': lambda s: s | dict(u=[[True] + r[1:] if i == 0 else r for i, r in enumerate(s['u'])]),
    'null_coefficient': lambda s: s | dict(w=[[None] + r[1:] if i == 0 else r for i, r in enumerate(s['w'])]),
    'text_coefficient': lambda s: s | dict(u=[['abc'] + r[1:] if i == 0 else r for i, r in enumerate(s['u'])]),
    'rational_zero_denominator': lambda s: s | dict(v=[['1/0'] + r[1:] if i == 0 else r for i, r in enumerate(s['v'])]),
    'rational_even_denominator': lambda s: s | dict(v=[['1/2'] + r[1:] if i == 0 else r for i, r in enumerate(s['v'])]),
    'rational_reduces_to_odd': lambda s: s | dict(v=[['2/2'] + r[1:] if i == 0 else r for i, r in enumerate(s['v'])]),
    'inexact': lambda s: s | dict(w=[[1 - r[0]] + r[1:] if i == 3 else r for i, r in enumerate(s['w'])]),
    'wrong_rank': lambda s: s | dict(m=19),
    'large_coefficients': lambda s: s | dict(u=[[2 ** 70 + 1] + r[1:] if i == 0 else r for i, r in enumerate(s['u'])]),
    'negative_coefficients': lambda s: s | dict(u=[[-1] + r[1:] if i == 0 else r for i, r in enumerate(s['u'])]),
}
for name, mutate in mutations.items():
    scheme = mutate(copy_of(bad))
    rank = scheme['m'] if isinstance(scheme.get('m'), int) else 18
    put(f'ZT/2x3x3_m{rank if name != "wrong_rank" else 18}_{name}_ZT.json', scheme)
# modulo two a repeated term cancels and a term with an even factor vanishes: the seed has a lower rank than the file
cancel = naive(2, 2, 4)
cancel.update(m=18, u=cancel['u'] + [cancel['u'][0], [3 * x for x in cancel['u'][0]]], v=cancel['v'] + [cancel['v'][0]] * 2,
              w=cancel['w'] + [cancel['w'][0]] * 2)
put('ZT/2x2x4_m18_cancelling_pair_ZT.json', cancel)
vanish = naive(2, 2, 5)
vanish.update(m=21, u=vanish['u'] + [[2, 0, 0, 0]], v=vanish['v'] + [vanish['v'][0]], w=vanish['w'] + [vanish['w'][0]])
put('ZT/2x2x5_m21_vanishing_term_ZT.json', vanish)
put('ZT/2x3x5_m30_broken_json_ZT.json', '{"n": [2, 3, 5], "m": 30,', raw=True)
put('ZT/2x3x5_m30_empty_ZT.json', '', raw=True)
put('ZT/2x3x5_m30_trailing_ZT.json', json.dumps(naive(2, 3, 5), separators=(',', ':')) + ' x', raw=True)
put('ZT/2x3x3_m17_name_rank_ZT.json', naive(2, 3, 3))  # the file name says 17, the scheme has 18 terms
put('notes/README.md', '# not a scheme\n', raw=True)
put('ZT/2x3x5_m30_ZT.jsonl', 'not json\n', raw=True)  # `.json` must end the name


def write_tree():
    if TREE.exists():
        shutil.rmtree(TREE)
    for path, text in FILES.items():
        target = TREE / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)


def git(repo, *args, **kwargs):
    return subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True, text=True,
                          env={**os.environ, **GIT_ENV}, **kwargs).stdout


def make_repo(target):
    shutil.copytree(TREE, target)
    git(target, 'init', '-q')
    git(target, 'add', '-f', '.')
    git(target, 'commit', '-q', '-m', 'fixture')
    return target


# ---- expected outputs ------------------------------------------------------------------------------

PARITY_VALUES = [
    '0', '1', '-1', '2', '-2', '3', '-3', '7', '-8', '1152921504606846976', '1180591620717411303425',
    '-1180591620717411303427', '"3/5"', '"-3/5"', '"4/6"', '"2/3"', '"6/4"', '"1/2"', '"0/5"', '"2/2"', '"007/3"',
    '"-0/3"', '"5/0"', '"3/"', '"/3"', '"1/-2"', '" 3/5"', '"3/5 "', '"3/5\\n"', '"1e3"', '"abc"', '""', '"-"', '"-/3"',
    '"123456789012345678901234567890/7"', '"-123456789012345678901234567891/7"', '"9/3"', '"10/4"', '"4/8"', '"3/05"',
    '1.0', '0.0', '2.5', 'true', 'false', 'null', '[1]', '{}', '[]',
]


def parity_table():
    lines = []
    for text in PARITY_VALUES:
        value = json.loads(text)
        try:
            outcome = f'ok {tool.parity(value)}'
        except Exception as exc:  # the tool's own ValueError
            outcome = f'error {exc}'
        lines.append(f'{text}\t{outcome}')
    return '\n'.join(lines) + '\n'


PARSE_TEXTS = [
    'seed_rank=21 rank=20 moves=1000 accepted=5 no_pair=2 escapes=0',
    'noise\nseed_rank=3 rank=3 moves=4 accepted=5 no_pair=6 escapes=7\n',
    'seed_rank=1 rank=2 moves=3 accepted=4 no_pair=5',
    'seed_rank=1 rank=2 moves=3 accepted=4 no_pair=5 escapes=',
    'seed_rank=x rank=2 moves=3 accepted=4 no_pair=5 escapes=6',
    'seed_rank=9 seed_rank=1 rank=2 moves=3 accepted=4 no_pair=5 escapes=6 rank=7',
    'seed_rank=1  rank=2 moves=3 accepted=4 no_pair=5 escapes=6',
    'seed_rank=100 rank=99 moves=40000000 accepted=123456 no_pair=0 escapes=9\nseed_rank=1 rank=1 moves=1 accepted=1 no_pair=1 escapes=1',
    '', 'seed_rank=', 'rank=2 moves=3',
]


def parse_table():
    lines = []
    for text in PARSE_TEXTS:
        match = tool.RESULT.search(text)
        found = 'none' if not match else ' '.join(match.group(1, 2, 3))
        lines.append(f'{json.dumps(text)}\t{found}')
    return '\n'.join(lines) + '\n'


def files_table(repo):
    result = {}
    for alternatives, rational in ((0, False), (1, False), (1, True), (2, True)):
        files = tool.integer_files(str(repo), 'HEAD', alternatives, rational)
        result[f'{alternatives},{rational}'] = {'x'.join(map(str, key)): [[rank, name] for rank, name in items]
                                                for key, items in sorted(files.items())}
    return json.dumps(result, indent=1, sort_keys=True) + '\n'


RUNS = {
    'default': ['--min-max-dim', '2'],
    'alternatives': ['--min-max-dim', '2', '--alternatives', '1'],
    'rational': ['--min-max-dim', '2', '--include-rational'],
    'rational_alternatives': ['--min-max-dim', '2', '--include-rational', '--alternatives', '2'],
    'everything': ['--min-max-dim', '2', '--include-rational', '--alternatives', '10'],
    'window': ['--min-dim', '2', '--min-max-dim', '3', '--max-dim', '8', '--include-rational', '--alternatives', '1'],
}


def run_seeds(repo, name, extra, work):
    out = work / f'out-{name}'
    proc = subprocess.run([sys.executable, str(BIT / 'tools/screen_public_ternary_gf2.py'), 'seeds', '--repo', str(repo),
                           '--url', URL, '--out', f'out-{name}', *extra],
                          cwd=work, capture_output=True, text=True, check=True, env={**os.environ, 'GIT_NO_LAZY_FETCH': '1'})
    target = EXPECTED / 'runs' / name
    target.mkdir(parents=True, exist_ok=True)
    (target / 'seeds.json').write_text((out / 'seeds.json').read_text())
    (target / 'summary.txt').write_text(proc.stdout)
    rows = []
    for path in sorted(out.glob('*.mfw')):
        rows.append(f'{path.name}\t{hashlib.sha256(path.read_bytes()).hexdigest()}')
    (target / 'mfw.tsv').write_text('\n'.join(rows) + ('\n' if rows else ''))
    return out


def walk_table(work, seeds_dir):
    # a manifest of the seeds of the `alternatives` run, renamed so the stub sees its instruction in the file name
    manifest = json.loads((seeds_dir / 'seeds.json').read_text())
    picks = []
    for index, row in enumerate(manifest['seeds']):
        tag = ['ok', 'drop', 'fail', 'noline', 'ok'][index % 5]
        source = seeds_dir / Path(row['mfw']).name
        renamed = source.with_name(f'{tag}-{source.name}')
        shutil.copy(source, renamed)
        copied = dict(row, mfw=str(renamed))
        if index == 4:
            del copied['mfw_sha256']
        picks.append(copied)
    (work / 'walk-manifest.json').write_text(json.dumps({'schema': 1, 'seeds': picks}))
    stub = work / 'walker_stub.sh'
    shutil.copy(HERE / 'walker_stub.sh', stub)
    stub.chmod(0o755)
    log = work / 'walk.jsonl'
    proc = subprocess.run([sys.executable, str(BIT / 'tools/screen_public_ternary_gf2.py'), 'walk', '--seeds', str(work / 'walk-manifest.json'),
                           '--walker', str(stub), '--out', str(log), '--steps', '5000', '--jobs', '3', '--repeats', '2',
                           '--nonce-base', '17'], cwd=work, capture_output=True, text=True, check=True)
    # the output of a seed without a hash is named after the hash of its path, which depends on the temporary directory
    path_tag = hashlib.sha256(picks[4]['mfw'].encode()).hexdigest()[:8]

    def normal(text):
        return text.replace(path_tag, '$PATHSHA').replace(str(work), '$TMP')
    text = normal('\n'.join(sorted(log.read_text().splitlines())) + '\n')
    stdout = normal(''.join(sorted(proc.stdout.splitlines(keepends=True))))
    outputs = sorted(normal(f'{p.name}\t{hashlib.sha256(p.read_bytes()).hexdigest()}') for p in (work / 'walk_mfw').glob('*.mfw'))
    return text, stdout, '\n'.join(outputs) + '\n'


def main():
    write_tree()
    (HERE / 'walker_stub.sh').write_text(STUB)
    (HERE / 'walker_stub.sh').chmod(0o755)
    if EXPECTED.exists():
        shutil.rmtree(EXPECTED)
    EXPECTED.mkdir(parents=True)
    (EXPECTED / 'parity.tsv').write_text(parity_table())
    (EXPECTED / 'parse_result.tsv').write_text(parse_table())
    work = Path(tempfile.mkdtemp(prefix='gf2-public-ternary-'))
    try:
        repo = make_repo(work / 'repo')
        (EXPECTED / 'integer_files.json').write_text(files_table(repo))
        (EXPECTED / 'revision.txt').write_text(git(repo, 'rev-parse', 'HEAD'))
        outs = {name: run_seeds(repo, name, extra, work) for name, extra in RUNS.items()}
        text, stdout, outputs = walk_table(work, outs['alternatives'])
        (EXPECTED / 'walk.tsv').write_text(text)
        (EXPECTED / 'walk_stdout.txt').write_text(stdout)
        (EXPECTED / 'walk_outputs.tsv').write_text(outputs)
    finally:
        shutil.rmtree(work)
    print('wrote', EXPECTED)


STUB = '''#!/bin/sh
# Stand-in for the compiled walker: walker_stub.sh SHAPE SEED.mfw OUTPUT.mfw STEPS NONCE
# The behaviour comes from the seed's file name: ok-, drop- (one rank less), fail- (exit 3), noline- (no result line).
seed="$2"
out="$3"
steps="$4"
name=$(basename "$seed")
rank=$(head -n 1 "$seed" | awk '{print $5}')
case "$name" in
  fail-*) echo "walker: cannot open $seed" >&2; exit 3 ;;
  noline-*) echo "done"; cp "$seed" "$out"; exit 0 ;;
  drop-*) new=$((rank - 1)) ;;
  *) new=$rank ;;
esac
cp "$seed" "$out"
echo "seed_rank=$rank rank=$new moves=$steps accepted=7 no_pair=2 escapes=1"
'''

if __name__ == '__main__':
    main()
