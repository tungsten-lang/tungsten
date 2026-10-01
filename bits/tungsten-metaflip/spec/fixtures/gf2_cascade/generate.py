#!/usr/bin/env python3
"""Regenerates spec/fixtures/gf2_cascade/ from the ORIGINAL drivers (tools/campaign/*.py, the oracles).

  generate.py [WALKER]

WALKER is the compiled tools/wide_rect_walk.w (built here with --release when it is not given). It writes, next to this file:

  in/witnesses/*.mfw      four seeds of the repository (3x3x4 r29, 3x4x4 r38, 2x3x5 r25, 3x3x5 r36) and two of rank 31 and 40 (3x3x4, 3x4x4) as MFW1
  in/lille.json           a dated rank table (fmm_sota.json layout) for the children of those shapes
  in/board.json           a scoreboard (gf2_record_board --json layout; `$WITNESS` stands for the witness directory)
  in/board_pick.json      the scoreboard that `pick` compares with
  in/screen_seeds.json, sweep_seeds.json, iter_seeds.json, filter.txt   the parents and seeds of the steps (`$WITNESS` as in board.json)
  in/proj-a.jsonl, proj-b.jsonl   two projection logs for `parents`
  in/walker-alt.sh        a stand-in walker (`$ALT` is in/alt): it prints and writes what the compiled walker did for the same output
                          name; in/alt/<name>.mfw and <name>.stdout are the real walker's answers for every walk of the cases below
  cases.json              the steps: {"name", "command", ...}; `{t}` stands for the scratch directory and `{in}` for in/
  expected/<step>/stdout.txt  what the step prints (scratch paths written `$T`), sorted for `iterate`
  expected/<step>/out.txt     its output file(s) with the scratch directory written `$T`: the JSON of `parents` and `pick`; the log of
                          `screen` and `sweep`; the log of `iterate` grouped by shape (the original interleaves shapes as they finish)
  expected/<step>/files.txt   the name and SHA-256 of every file the step wrote next to its output (children, walker outputs)

Each step runs the original script in a process of its own, from a scratch directory that holds copies of the originals with their
machine-specific constants rewritten (the tools directory, the rank tables of pub.py, the walker). Everything here is derived from the
Python originals, never from the Tungsten port.
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
ROOT = BIT.parents[1]
sys.path[:0] = [str(BIT / 'tools'), str(BIT / 'spec')]
os.environ.setdefault('PYTHONDONTWRITEBYTECODE', '1')
import gf2_record_board as grb  # noqa: E402
import screen_top_two_projection_children as top  # noqa: E402

IN = HERE / 'in'
EXPECTED = HERE / 'expected'
SEEDS = BIT / 'lib/metaflip/seeds/gf2'
CAMPAIGN = BIT / 'tools/campaign'
WITNESSES = {
    '334': 'matmul_3x3x4_rank29_gf2.txt', '344': 'matmul_3x4x4_rank38_gf2.txt',
    '235': 'matmul_2x3x5_rank25_d160_fleet_gf2.txt', '335': 'matmul_3x3x5_rank36_d287_gf2.txt',
    '334b': 'matmul_3x3x4_rank31_peterson_2026_isotropy_split_plus2_parent_5314db3816_gf2.txt',
    '344b': 'matmul_3x4x4_rank40_peterson_2026_isotropy_split_plus2_parent_8aa9879491_gf2.txt',
}
PUBLIC = [([2, 2, 2], 7), ([2, 2, 3], 11), ([2, 2, 4], 14), ([2, 3, 3], 15), ([2, 3, 4], 20), ([2, 3, 5], 25), ([3, 3, 3], 23),
          ([3, 3, 4], 29), ([2, 4, 4], 26), ([3, 4, 4], 38), ([3, 3, 5], 36), ([2, 4, 5], 33), ([2, 5, 5], 40)]
# kinds are the scoreboard's (below_all, gf2_valid_only, tie, above); the ranks of the rows are what the fixture says they are
BOARD = [('3x3x4', 29, 'below_all', 'w/334.mfw'), ('3x4x4', 38, 'gf2_valid_only', 'w/344.mfw'), ('2x3x5', 25, 'tie', 'w/235.mfw'),
         ('3x3x5', 36, 'above', 'w/335.mfw'), ('3x3x4', 31, 'tie', 'w/334b.mfw'), ('3x4x4', 40, 'above', 'w/344b.mfw'),
         ('2x2x2', 7, 'tie', 'w/missing-a.mfw'), ('2x2x3', 11, 'below_all', 'w/missing-b.mfw'), ('2x2x4', 14, 'below_all', 'w/missing-c.mfw')]
BOARD_PICK = [dict(shape='3x3x3', rank=24), dict(shape='2x3x4', rank=21), dict(shape='2x4x4', rank=27), dict(shape='3x3x4', rank=29),
              dict(shape='2x3x5', rank=25), dict(shape='2x4x5', rank=33)]
WALK = ['--steps', '20000']
STEPS = [
    dict(name='parents-default', command='parents', board='{t}/board.json', out='{t}/parents-default.json', logs=['{in}/proj-a.jsonl']),
    dict(name='parents-kinds', command='parents', board='{t}/board.json', out='{t}/parents-kinds.json',
         logs=['{in}/proj-a.jsonl', '{in}/proj-b.jsonl'], kinds='tie,above'),
    dict(name='screen', command='screen', seeds='{t}/screen_seeds.json', out='{t}/proj.jsonl', mfw_dir='{t}/proj_mfw'),
    dict(name='screen-again', command='screen', seeds='{t}/screen_seeds.json', out='{t}/proj.jsonl', mfw_dir='{t}/proj_mfw'),
    dict(name='pick-003', command='pick', proj='{t}/proj.jsonl', board='{t}/board_pick.json', out='{t}/pick-003.json', tolerance='0.03'),
    dict(name='pick-0', command='pick', proj='{t}/proj.jsonl', board='{t}/board_pick.json', out='{t}/pick-0.json', tolerance='0'),
    dict(name='pick-big', command='pick', proj='{t}/proj.jsonl', board='{t}/board_pick.json', out='{t}/pick-big.json', tolerance='0.5'),
    dict(name='sweep', command='sweep', seeds='{t}/sweep_seeds.json', out='{t}/sw/sweep.jsonl', walker='{t}/walker-alt.sh', steps=20000,
         jobs=1, nonce_base=17, filter='{t}/filter.txt', repeats=2),
    dict(name='sweep-again', command='sweep', seeds='{t}/sweep_seeds.json', out='{t}/sw/sweep.jsonl', walker='{t}/walker-alt.sh', steps=20000,
         jobs=1, nonce_base=17, filter='{t}/filter.txt', repeats=2),
    dict(name='iterate', command='iterate', seeds='{t}/iter_seeds.json', log='{t}/it/iter.jsonl', walker='{t}/walker-alt.sh', steps=20000,
         walks_per_round=2, patience=2, jobs=2, nonce_base=5),
]
RECORDER = '#!/bin/sh\nout=$(basename "$3")\n"$REAL" "$@" > "$ALT/$out.stdout"\ncode=$?\ncat "$ALT/$out.stdout"\ncp "$3" "$ALT/$out"\nexit $code\n'
ALT = '#!/bin/sh\nout=$(basename "$3")\ncat "$ALT/$out.stdout"\ncp "$ALT/$out" "$3"\n'


def decoded(name):
    path = SEEDS / WITNESSES[name]
    shape, terms = grb.decode(path, path.read_bytes())
    return tuple(shape), terms


def write_inputs():
    if IN.exists():
        shutil.rmtree(IN)
    (IN / 'witnesses').mkdir(parents=True)
    (IN / 'alt').mkdir()
    for name in WITNESSES:
        shape, terms = decoded(name)
        (IN / 'witnesses' / f'{name}.mfw').write_bytes(top.blob(shape, sorted(terms)))
    (IN / 'lille.json').write_text(json.dumps(dict(entries=[dict(format=f, rank=r) for f, r in PUBLIC]), indent=1) + '\n')
    rows = []
    for shape, rank, kind, path in BOARD:
        rows.append(dict(shape=shape, rank=rank, kind=kind, lille=None, best_any=None, best_gf2_valid=None,
                         path='$WITNESS/' + path.split('/', 1)[1]))
    (IN / 'board.json').write_text(json.dumps(rows, indent=1) + '\n')
    (IN / 'board_pick.json').write_text(json.dumps(BOARD_PICK, indent=1) + '\n')
    # a log that already projected two of the witnesses (and one that did not exist on the board), and one with a row without a shape
    (IN / 'proj-a.jsonl').write_text(
        json.dumps(dict(parent='$WITNESS/344.mfw', shape='3x3x4', rank=29)) + '\n' +
        json.dumps(dict(parent='$WITNESS/missing-b.mfw', shape=None)) + '\n')
    (IN / 'proj-b.jsonl').write_text(json.dumps(dict(parent='$WITNESS/334b.mfw', shape='2x3x4', rank=22)) + '\n')
    (IN / 'screen_seeds.json').write_text(json.dumps(seeds_json(['334', '344', '235', '335'], 'screen'), indent=1) + '\n')
    sweep = seeds_json(['334b', '344b', '235', '335'], 'sweep')
    (IN / 'sweep_seeds.json').write_text(json.dumps(sweep, indent=1) + '\n')
    (IN / 'iter_seeds.json').write_text(json.dumps(sweep[:3], indent=1) + '\n')
    (IN / 'filter.txt').write_text(' '.join(r['canonical'] for r in sweep[:3]) + '\n')
    (IN / 'walker-alt.sh').write_text(ALT)
    (HERE / 'cases.json').write_text(json.dumps(STEPS, indent=1) + '\n')


def seeds_json(names, kind):
    rows = []
    for name in names:
        shape, terms = decoded(name)
        text = 'x'.join(map(str, sorted(shape)))
        row = dict(shape=text, canonical=text, gf2_rank=len(terms), mfw=f'$WITNESS/{name}.mfw')
        if kind == 'screen':
            row['kind'] = 'below_all'
        rows.append(row)
    return rows


def prepare(scratch, walker_script):
    s = Path(scratch)
    shutil.copytree(IN / 'witnesses', s / 'witnesses')
    (s / 'logs').mkdir()
    for name in ('board.json', 'proj-a.jsonl', 'proj-b.jsonl', 'screen_seeds.json', 'sweep_seeds.json', 'iter_seeds.json'):
        (s / name).write_text((IN / name).read_text().replace('$WITNESS', str(s / 'witnesses')))
    shutil.copy(IN / 'board_pick.json', s / 'board_pick.json')
    shutil.copy(IN / 'filter.txt', s / 'filter.txt')
    path = s / 'walker-alt.sh'
    path.write_text(walker_script)
    path.chmod(0o755)
    (s / 'sw').mkdir()
    (s / 'it').mkdir()


def originals(scratch):
    """Copies of the oracles with their machine-specific constants rewritten, and a pub.py for the fixture's rank table."""
    target = Path(scratch) / 'orig'
    target.mkdir()
    tools = str(BIT / 'tools')
    for name in ('next_parents', 'project_screen', 'pick_children', 'sweep', 'iterate'):
        text = (CAMPAIGN / f'{name}.py').read_text()
        text = text.replace('/Users/erik/tungsten-mf-ternary/bits/tungsten-metaflip/tools', tools)
        (target / f'{name}.py').write_text(text)
    (target / 'pub.py').write_text(
        '"""Public comparator tables of the fixture."""\n'
        'import sys\nfrom types import SimpleNamespace\n'
        f'sys.path.insert(0, {tools!r})\nimport gf2_record_board as grb\n\n\n'
        'def tables():\n'
        f'    args = SimpleNamespace(lille={str(IN / "lille.json")!r}, matmulcatalog=None, fmm_repo=None, fmm_revision="HEAD", extra_repo=[])\n'
        '    return grb.public_tables(args)\n')
    os.symlink(Path(scratch) / 'walker-alt.sh', target / 'wide-rect-walk')   # the scripts look for the walker beside themselves
    return target


def expand(text, scratch):
    return text.replace('{t}', scratch).replace('{in}', str(IN))


def python_args(step, scratch, orig):
    c = step['command']
    f = lambda key: expand(step[key], scratch)  # noqa: E731
    if c == 'parents':
        args = ['next_parents.py', f('board'), f('out')] + [expand(x, scratch) for x in step['logs']]
        return args + (['--kinds=' + step['kinds']] if 'kinds' in step else []), {}
    if c == 'screen':
        return ['project_screen.py', f('seeds'), f('out'), '1'], {}
    if c == 'pick':
        return ['pick_children.py', f('proj'), f('board'), f('out'), step['tolerance']], {}
    if c == 'sweep':
        return ['sweep.py', f('seeds'), f('out'), str(step['steps']), str(step['jobs']), str(step['nonce_base']), f('filter')], \
            {'SWEEP_REPEATS': str(step['repeats'])}
    return ['iterate.py', f('seeds'), f('log'), str(step['steps']), str(step['walks_per_round']), str(step['patience']),
            str(step['jobs']), str(step['nonce_base'])], {}


def output_of(step, scratch):
    if step['command'] in ('parents', 'pick', 'screen', 'sweep'):
        return Path(expand(step['out'], scratch))
    return Path(expand(step['log'], scratch))


def snapshot(step, scratch):
    out = output_of(step, scratch)
    text = out.read_text().replace(scratch + '/orig/proj_mfw', scratch + '/proj_mfw').replace(scratch, '$T')
    if step['command'] == 'iterate':
        groups = {}
        for line in text.splitlines():
            groups.setdefault(json.loads(line)['shape'], []).append(line)
        text = ''.join(f'{shape}\t{line}\n' for shape in sorted(groups) for line in groups[shape])
    files = []
    dirs = {'screen': Path(scratch) / 'orig' / 'proj_mfw', 'sweep': out.parent / (out.stem + '_mfw'),
            'iterate': out.parent / (out.stem + '_mfw')}
    d = dirs.get(step['command'])
    if d is not None and d.exists():
        files = [f'{p.name} {hashlib.sha256(p.read_bytes()).hexdigest()}\n' for p in sorted(d.iterdir())]
    return text, ''.join(files)


def run_steps(scratch, orig, walker_script, record_to=None):
    results = {}
    for step in STEPS:
        args, extra = python_args(step, scratch, orig)
        run = subprocess.run([sys.executable, *args], capture_output=True, text=True, cwd=str(orig),
                             env={**os.environ, 'PYTHONDONTWRITEBYTECODE': '1', **extra})
        assert run.returncode == 0, (step['name'], run.stderr[-600:])
        stdout = run.stdout.replace(scratch + '/orig/proj_mfw', scratch + '/proj_mfw').replace(scratch, '$T')
        if step['command'] == 'iterate':
            stdout = ''.join(sorted(line + '\n' for line in stdout.splitlines()))
        text, files = snapshot(step, scratch)
        results[step['name']] = (stdout, text, files)
    return results


def main():
    if EXPECTED.exists():
        shutil.rmtree(EXPECTED)
    EXPECTED.mkdir()
    write_inputs()
    walker = sys.argv[1] if len(sys.argv) > 1 else None
    first = Path(tempfile.mkdtemp(prefix='gf2-cascade-a-')).resolve()   # the originals resolve their own directory
    second = Path(tempfile.mkdtemp(prefix='gf2-cascade-b-')).resolve()
    try:
        if walker is None:
            walker = str(first / 'wide_rect_walk')
            subprocess.run([str(ROOT / 'bin/tungsten'), '--release', '-o', walker, str(BIT / 'tools/wide_rect_walk.w')], check=True,
                           cwd=str(ROOT))
        # 1. the originals with the real walker, recording its answers
        scratch = str(first)
        recorder = RECORDER.replace('$REAL', walker).replace('$ALT', str(IN / 'alt'))
        prepare(scratch, recorder)
        orig = originals(scratch)
        real = run_steps(scratch, orig, recorder)
        print('real walker:', len(list((IN / 'alt').glob('*.mfw'))), 'walks recorded')
        # 2. the originals with the stand-in walker: the goldens
        scratch2 = str(second)
        stand_in = ALT.replace('$ALT', str(IN / 'alt'))
        prepare(scratch2, stand_in)
        orig2 = originals(scratch2)
        goldens = run_steps(scratch2, orig2, stand_in)

        def comparable(results, scratch_dir):
            return {k: tuple(v.replace(scratch_dir, '$T') for v in vs) for k, vs in results.items()}
        assert comparable(real, scratch) == comparable(goldens, scratch2), 'the stand-in walker answers differently from the real one'
        for step in STEPS:
            target = EXPECTED / step['name']
            target.mkdir()
            stdout, text, files = goldens[step['name']]
            (target / 'stdout.txt').write_text(stdout)
            (target / 'out.txt').write_text(text)
            (target / 'files.txt').write_text(files)
    finally:
        shutil.rmtree(first)
        shutil.rmtree(second)
    print('wrote', len(STEPS), 'steps')


if __name__ == '__main__':
    main()
