#!/usr/bin/env python3
"""Regenerates spec/fixtures/gf2_projection_walks/ from the ORIGINAL driver (tools/search_wide_projection_walks.py, the oracle).

  generate.py [WALKER]

WALKER is the compiled tools/wide_rect_walk.w (built here with --release when it is not given). It writes, next to this file:

  in/seed.mfw            the 3x3x4 rank-29 seed of the repository, as an MFW1 file
  in/other-shape.mfw     Strassen's <2,2,2>, for a walker that answers with the wrong shape
  in/public.json         a dated rank table (fmm_sota.json layout) for the children of the seed
  in/walker-*.sh         stand-in walkers (`$ALT` is the directory with the results below): `alt` answers with the real walker's
                         result for the seed it is given, `corrupt` writes garbage, `shape` another shape, `fail` exits 3
  in/alt/<name>.mfw      what the compiled walker returned (20,000 proposals, nonces from 7) for every walk of the depth-2 search
  cases.json             the cases: {"name", "args", "expect"}; `{t}` stands for the scratch directory, `{in}` for in/
  expected/<case>/stdout.txt, manifest.json, files.txt   for the cases that end well: what the original prints, its manifest (scratch
                         paths written `$T`) and the name and SHA-256 of every file it leaves next to it

Every case runs the original in a process of its own, with the stand-in walkers (the real walker's answers are in alt/, so the specs need
no compiled walker). Everything here is derived from the Python original, never from the Tungsten port.
"""
import hashlib
import itertools
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
BIT = HERE.parents[2]
ROOT = BIT.parents[1]
sys.path[:0] = [str(BIT / 'tools'), str(BIT / 'spec')]
os.environ.setdefault('PYTHONDONTWRITEBYTECODE', '1')
import gf2_record_board as grb  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402

IN = HERE / 'in'
EXPECTED = HERE / 'expected'
SEED = BIT / 'lib/metaflip/seeds/gf2/matmul_3x3x4_rank29_gf2.txt'
STRASSEN = BIT / 'lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt'
PUBLIC = [([2, 2, 2], 7), ([2, 2, 3], 11), ([2, 2, 4], 14), ([2, 3, 3], 15), ([2, 3, 4], 20), ([3, 3, 3], 23), ([3, 3, 4], 29),
          ([2, 4, 4], 26), ([3, 4, 4], 38)]
WALK = ['--steps', '20000', '--nonce-base', '7', '--depth', '2', '--beam', '2']
WALKERS = {
    'alt': '#!/bin/sh\nname=$(basename "$2" -seed.mfw)\ncp "$ALT/$name.mfw" "$3"\n',
    'corrupt': '#!/bin/sh\nprintf garbage > "$3"\n',
    'shape': '#!/bin/sh\ncp "$IN/other-shape.mfw" "$3"\n',
    'fail': '#!/bin/sh\nexit 3\n',
}
# name, arguments, whether the original ends well
CASES = [
    ('list-only', ['--seed', '{t}/seed.mfw', '--digest', '{in}/public.json', '--beam', '3', '--list-only'], True),
    ('walk', ['--seed', '{t}/seed.mfw', '--digest', '{in}/public.json', '--walker', '{t}/walker-alt.sh', '--output-dir',
              '{t}/out-walk'] + WALK, True),
    ('walk-shallow', ['--seed', '{t}/seed.mfw', '--digest', '{in}/public.json', '--walker', '{t}/walker-alt.sh', '--output-dir',
                      '{t}/out-shallow', '--steps', '20000', '--nonce-base', '7', '--depth', '1', '--beam', '1'], True),
    ('corrupt', ['--seed', '{t}/seed.mfw', '--digest', '{in}/public.json', '--walker', '{t}/walker-corrupt.sh', '--output-dir',
                 '{t}/out-corrupt'] + WALK, False),
    ('other-shape', ['--seed', '{t}/seed.mfw', '--digest', '{in}/public.json', '--walker', '{t}/walker-shape.sh', '--output-dir',
                     '{t}/out-shape'] + WALK, False),
    ('failing', ['--seed', '{t}/seed.mfw', '--digest', '{in}/public.json', '--walker', '{t}/walker-fail.sh', '--output-dir',
                 '{t}/out-fail'] + WALK, False),
    ('existing-directory', ['--seed', '{t}/seed.mfw', '--digest', '{in}/public.json', '--walker', '{t}/walker-alt.sh',
                            '--output-dir', '{t}/out-walk'] + WALK, False),
    ('nonce-range', ['--seed', '{t}/seed.mfw', '--digest', '{in}/public.json', '--walker', '{t}/walker-alt.sh', '--output-dir',
                     '{t}/out-nonce', '--steps', '20000', '--nonce-base', '2147483647', '--depth', '1', '--beam', '2'], False),
    ('conflicting-public', ['--seed', '{t}/seed.mfw', '--digest', '{in}/conflict.json', '--beam', '2', '--list-only'], False),
]


def seed_blob():
    raw = SEED.read_bytes()
    shape, terms = grb.decode(SEED, raw)
    assert tuple(shape) == (3, 3, 4) or sorted(shape) == [3, 3, 4]
    return top.blob(tuple(shape), sorted(terms))


def strassen_blob():
    shape, terms = grb.decode(STRASSEN, STRASSEN.read_bytes())
    return top.blob(tuple(shape), sorted(terms))


def expand(args, scratch):
    return [a.replace('{t}', scratch).replace('{in}', str(IN)) for a in args]


def python_run(args, scratch):
    return subprocess.run([sys.executable, str(BIT / 'tools/search_wide_projection_walks.py'), *args], capture_output=True,
                          text=True, cwd=scratch, env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1'})


def setup(scratch):
    shutil.copy(IN / 'seed.mfw', Path(scratch) / 'seed.mfw')
    for name, text in WALKERS.items():
        path = Path(scratch) / f'walker-{name}.sh'
        path.write_text(text.replace('$ALT', str(IN / 'alt')).replace('$IN', str(IN)))
        path.chmod(0o755)


def snapshot(out, scratch):
    manifest = (out / 'manifest.json').read_text().replace(scratch, '$T')
    files = ''.join(f'{p.name} {hashlib.sha256(p.read_bytes()).hexdigest()}\n'
                    for p in sorted(out.iterdir()) if p.name != 'manifest.json')
    return manifest, files


def main():
    if EXPECTED.exists():
        shutil.rmtree(EXPECTED)
    if IN.exists():
        shutil.rmtree(IN)
    (IN / 'alt').mkdir(parents=True)
    EXPECTED.mkdir()
    (IN / 'seed.mfw').write_bytes(seed_blob())
    (IN / 'other-shape.mfw').write_bytes(strassen_blob())
    (IN / 'public.json').write_text(json.dumps(dict(entries=[dict(format=f, rank=r) for f, r in PUBLIC]), indent=1) + '\n')
    (IN / 'conflict.json').write_text(json.dumps(dict(entries=[dict(format=[2, 3, 4], rank=20), dict(format=[4, 3, 2], rank=21)]),
                                                 indent=1) + '\n')
    for name, text in WALKERS.items():
        (IN / f'walker-{name}.sh').write_text(text)
    walker = sys.argv[1] if len(sys.argv) > 1 else None
    work = Path(tempfile.mkdtemp(prefix='gf2-projwalks-'))
    scratch = str(work)
    try:
        if walker is None:
            walker = str(work / 'wide_rect_walk')
            subprocess.run([str(ROOT / 'bin/tungsten'), '--release', '-o', walker, str(BIT / 'tools/wide_rect_walk.w')], check=True,
                           cwd=str(ROOT))
        # the real walker's answers for the depth-2 search
        real = work / 'real'
        shutil.copy(IN / 'seed.mfw', work / 'seed.mfw')
        run = python_run(['--seed', scratch + '/seed.mfw', '--digest', str(IN / 'public.json'), '--walker', walker, '--output-dir',
                          str(real)] + WALK, scratch)
        assert run.returncode == 0, run.stderr
        for path in sorted(real.glob('d*-result.mfw')):
            shutil.copy(path, IN / 'alt' / path.name.replace('-result', ''))
        print('real walker:', len(list((IN / 'alt').iterdir())), 'walks')
        real_manifest = json.loads((real / 'manifest.json').read_text())
        setup(scratch)
        cases = []
        for name, args, ends_well in CASES:
            expanded = expand(args, scratch)
            run = python_run(expanded, scratch)
            assert (run.returncode == 0) == ends_well, (name, run.returncode, run.stderr[-400:])
            cases.append(dict(name=name, args=args, expect='ok' if ends_well else 'rejected'))
            if not ends_well:
                continue
            target = EXPECTED / name
            target.mkdir()
            (target / 'stdout.txt').write_text(run.stdout.replace(scratch, '$T'))
            if '--list-only' not in args:
                out = Path(expanded[expanded.index('--output-dir') + 1])
                manifest, files = snapshot(out, scratch)
                (target / 'manifest.json').write_text(manifest)
                (target / 'files.txt').write_text(files)
        # the stand-in walker answers exactly as the real one did
        walk = json.loads((EXPECTED / 'walk' / 'manifest.json').read_text().replace('$T', scratch))
        assert [r['result_sha256'] for r in walk['rows']] == [r['result_sha256'] for r in real_manifest['rows']]
        (HERE / 'cases.json').write_text(json.dumps(cases, indent=1) + '\n')
    finally:
        shutil.rmtree(work)
    print('wrote', len(CASES), 'cases')


if __name__ == '__main__':
    main()
