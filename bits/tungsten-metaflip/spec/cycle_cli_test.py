#!/usr/bin/env python3
"""Focused real-executable rotation, checkpoint, and terminal-stop checks."""
import os
from pathlib import Path
import pty
import re
import select
import signal
import subprocess
import sys
import tempfile
import time

BINARY = Path(os.environ.get('METAFLIP_TEST_BINARY', Path(__file__).resolve().parents[1] / 'bin/metaflip')).resolve()
RUNTIME = Path(__file__).resolve().parents[1] / 'lib/metaflip'


def fields(path):
    if not path.exists():
        return {}
    return dict(token.split('=', 1) for token in path.read_text().split() if '=' in token)


def run(args, timeout=40):
    return subprocess.run([str(BINARY), '--runtime-root', str(RUNTIME), *args],
                          text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)


def check_terminal_stop(root, shape, key):
    path = root / ('terminal-' + shape + '-' + str(key[0]))
    path.mkdir()
    status = path / 'status.txt'
    pid, master = pty.fork()
    if pid == 0:
        os.execv(str(BINARY), [str(BINARY), '--runtime-root', str(RUNTIME), '--cycle-shapes', shape + ',3x3',
                              '--cycle-secs', '60', '-J', '1', '--steps', '200', '--no-gpu', '--tui',
                              '--state-dir', str(path), '--status', str(status)])
    output = bytearray()
    sent = False
    done = False
    deadline = time.monotonic() + 30
    try:
        while time.monotonic() < deadline:
            readable, _, _ = select.select([master], [], [], 0.05)
            if readable:
                try:
                    output.extend(os.read(master, 65536))
                except OSError:
                    pass
            live = fields(status)
            if not sent and live.get('producer_state') in ('LIVE', 'running'):
                os.write(master, key)
                sent = True
            waited, code = os.waitpid(pid, os.WNOHANG)
            if waited:
                assert os.waitstatus_to_exitcode(code) == 0, output[-6000:].decode(errors='replace')
                done = True
                break
        assert sent and done, output[-6000:].decode(errors='replace')
        body = fields(status)
        assert body['tensor'] == shape and body['cycle_visit'] == '0', body
        assert body['producer_state'] in ('DONE', 'stopped'), body
        assert b'tensor=3x3' not in output, 'q/Ctrl-C advanced to another shape'
    finally:
        if not done:
            os.killpg(pid, signal.SIGTERM)
            time.sleep(0.2)
            try:
                os.killpg(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)
        os.close(master)

def check_terminal_next(root, shapes):
    """`n` ends the current visit early and the cycle continues with the next shape."""
    path = root / ('next-' + shapes.replace(',', '_'))
    status = path / 'status.txt'
    pid, master = pty.fork()
    if pid == 0:
        os.execv(str(BINARY), [str(BINARY), '--runtime-root', str(RUNTIME), '--cycle-shapes', shapes,
                              '--cycle-secs', '60', '--secs', '12', '-J', '1', '--steps', '200', '--no-gpu', '--tui',
                              '--state-dir', str(path), '--status', str(status)])
    output = bytearray()
    sent = False
    done = False
    started = time.monotonic()
    deadline = started + 45
    try:
        while time.monotonic() < deadline:
            readable, _, _ = select.select([master], [], [], 0.05)
            if readable:
                try:
                    output.extend(os.read(master, 65536))
                except OSError:
                    pass
            live = fields(status)
            if not sent and live.get('producer_state') in ('LIVE', 'running'):
                os.write(master, b'n')
                sent = True
            waited, code = os.waitpid(pid, os.WNOHANG)
            if waited:
                assert os.waitstatus_to_exitcode(code) == 0, output[-6000:].decode(errors='replace')
                done = True
                break
        text = output.decode(errors='replace')
        assert sent and done, text[-6000:]
        first, second = shapes.split(',')
        assert 'tensor=' + second in text, text[-6000:]
        assert time.monotonic() - started < 40, 'n did not cut the 60 s visit short'
    finally:
        os.close(master)



with tempfile.TemporaryDirectory(prefix='metaflip-cycle-check-') as temp:
    root = Path(temp)
    for args, message in [(['--cycle-secs', '0'], '--cycle-secs'),
                          (['--cycle-policy', 'bogus'], '--cycle-policy'),
                          (['--cycle-shapes', '5x5,05x05'], '--cycle-shapes'),
                          (['--cycle-shapes', ''], '--cycle-shapes'),
                          (['--cycle-shapes', '5x5,'], '--cycle-shapes'),
                          (['--tensor', '5x5', '--cycle-secs', '1'], 'conflicts'),
                          (['--rect', '--cycle-secs', '1'], 'conflicts'),
                          (['--best', str(root / 'wrong-best')], 'shape-specific')]:
        result = run(args)
        assert result.returncode == 2 and message in result.stdout, (args, result.stdout)

    state = root / 'rotation'
    result = run(['--cycle-shapes', '2x2,2x2x5', '--cycle-secs', '1', '--secs', '5', '-J', '1',
                  '--steps', '200', '--no-gpu', '--no-tui', '--state-dir', str(state)], timeout=25)
    assert result.returncode == 0, result.stdout[-8000:]
    visits = re.findall(r'metaflip cycle: tensor=(\S+) .*?cycle_visit=(\d+)', result.stdout)
    assert len(visits) >= 3 and visits[:3] == [('2x2', '0'), ('2x2x5', '1'), ('2x2', '2')], visits
    for shape in ('2x2x2', '2x2x5'):
        assert (state / 'checkpoints/gf2' / shape / 'best.txt').exists()
        statuses = list((state / 'runs/gf2' / shape).glob('*/status.txt'))
        assert len(statuses) == 1, 'run tag changed, stranding the per-shape refinement queue'
        data = fields(statuses[0])
        assert data['cycle_count'] == '2' and data['cycle_seconds'] == '1', data
        assert data.get('exact_rejects', '0') == '0', data
        assert data['search_purpose'] == 'composition-parent', data
        assert data['proven_rank'] == ('7' if shape == '2x2x2' else '18'), data
        if shape == '2x2x2':
            assert data['mode'] == 'optimal-parent' and data['cpu_lanes'] == '0', data
            assert data['orbit_codes'] == '216' and data['refine_submitted'] == '36', data

    pinned = run(['--tensor', '2x2', '--rounds', '1', '--steps', '10', '-J', '1', '--no-gpu', '--no-tui',
                  '--state-dir', str(root / 'pinned')])
    assert pinned.returncode == 0 and 'metaflip cycle:' not in pinned.stdout, pinned.stdout
    assert pinned.stdout.count('metaflip native done:') == 1
    # Default uses the adaptive parent slice; uniform restores the full ceiling.
    default = run(['--secs', '1', '--steps', '100', '-J', '1', '--no-gpu', '--no-tui',
                   '--state-dir', str(root / 'default')])
    assert default.returncode == 0 and 'cycle_count=34 cycle_seconds=15' in default.stdout, default.stdout
    uniform = run(['--cycle-policy', 'uniform', '--secs', '1', '-J', '1', '--no-gpu', '--no-tui',
                   '--state-dir', str(root / 'uniform')])
    assert uniform.returncode == 0 and 'cycle_count=34 cycle_seconds=60' in uniform.stdout, uniform.stdout
    unresolved = run(['--cycle-shapes', '3x3', '--secs', '1', '--steps', '100', '-J', '1', '--no-gpu', '--no-tui',
                      '--state-dir', str(root / 'unresolved')])
    assert unresolved.returncode == 0 and 'search_purpose=rank-search proven_rank=0' in unresolved.stdout, unresolved.stdout
    shared = root / 'shared-status.txt'
    shared_run = run(['--cycle-shapes', '2x2,2x2x5', '--cycle-secs', '1', '--secs', '4',
                      '--steps', '100', '-J', '1', '--no-gpu', '--no-tui',
                      '--state-dir', str(root / 'shared'), '--status', str(shared)])
    assert shared_run.returncode == 0, shared_run.stdout
    assert 'tensor=2x2x5' in shared_run.stdout
    assert fields(shared)['refine_failures'] == '0', fields(shared)
    assert Path(str(shared)+'.refinement/composition/utility/source').read_text() == 'mixed\n'
    for shape in ('2x2', '2x2x5'):
        check_terminal_stop(root, shape, b'q')
        check_terminal_stop(root, shape, b'\x03')
    check_terminal_next(root, '2x2x5,2x2')

print('PASS mixed cycling, resume paths, pinning, default dwell, n, q and Ctrl-C')
