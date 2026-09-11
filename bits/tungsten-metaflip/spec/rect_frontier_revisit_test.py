#!/usr/bin/env python3
"""A rectangular campaign must start again after adopting a later frontier
slot as its durable best.

The first visit to a shape whose packaged frontier holds a lower-density
door than slot 0 adopts that door as the density leader and checkpoints it.
The revisit then loads best.txt equal to that frontier slot; that is not a
packaging duplicate and must not abort the campaign (it once returned
RECT_ERROR code=frontier-duplicate and ended the whole cycle).
No rank-record claim: both visits tie the packaged reference rank.
"""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

BINARY = Path(os.environ.get('METAFLIP_TEST_BINARY', Path(__file__).resolve().parents[1] / 'bin/metaflip')).resolve()
RUNTIME = Path(__file__).resolve().parents[1] / 'lib/metaflip'
SHAPE = '3x3x5'   # slot 1 (AlphaTensor-Z d265) is denser-lighter than slot 0
RANK = 36


def visit(state, secs):
    return subprocess.run([str(BINARY), '--runtime-root', str(RUNTIME), '--tensor', SHAPE, '--no-gpu', '--no-tui',
                           '-J', '2', '--secs', str(secs), '--state-dir', str(state)],
                          capture_output=True, text=True, timeout=240)


def main():
    if not BINARY.exists():
        print(f'SKIP rect frontier revisit: {BINARY} is not built')
        return 0
    state = Path(tempfile.mkdtemp(prefix='metaflip-frontier-revisit-'))
    try:
        first = visit(state, 4)
        best = state / 'checkpoints' / 'gf2' / SHAPE / 'best.txt'
        if 'RECT_ERROR' in first.stdout or first.returncode != 0 or not best.exists():
            print('FAIL first visit', first.returncode, (first.stdout + first.stderr)[-600:])
            return 1
        # Force the revisit condition regardless of which door the short first
        # visit happened to lead with: make best.txt exactly frontier slot 1.
        slot1 = next(RUNTIME.glob(f'seeds/gf2/matmul_{SHAPE}_rank{RANK}_d265_*_gf2.txt'))
        shutil.copyfile(slot1, best)
        second = visit(state, 4)
        out = second.stdout + second.stderr
        if 'RECT_ERROR' in out or second.returncode != 0:
            print('FAIL revisit', second.returncode, out[-800:])
            return 1
        if f'RECT_RESULT tensor={SHAPE} rank={RANK}' not in out:
            print('FAIL revisit produced no exact result', out[-800:])
            return 1
        print(f'PASS rect frontier revisit: {SHAPE} best equal to frontier slot 1 restarts and ties rank {RANK} (no rank-record claim)')
        return 0
    finally:
        shutil.rmtree(state, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
