#!/usr/bin/env python3
"""Opt-in one-lane routing, exact endpoints, invalid options, and bounded stop."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from import_wide_seeds import verify
BINARY = Path(os.environ.get('METAFLIP_TEST_BINARY', ROOT/'bin/metaflip')).resolve()

def run(mode, state, *extra):
    env = dict(os.environ, METAFLIP_WIDE_DIRECTED=mode)
    return subprocess.run([str(BINARY), '--runtime-root', str(ROOT/'lib/metaflip'),
                           '--tensor', '16x16', '--state-dir', str(state), '--status', str(state/'status'),
                           '--no-gpu', '--no-tui', '-J', '2', '--steps', '4096', '--rounds', '3', *extra],
                          env=env, text=True, capture_output=True, timeout=20)

def check(state):
    values = dict(item.split('=', 1) for item in (state/'status').read_text().split())
    raw = (state/'checkpoints/gf2/16x16x16/best.txt').read_text().splitlines()
    assert raw[0].split()[:4] == ['MFW1', '16', '16', '16']
    terms = [tuple(int(v, 16) for v in line.split()) for line in raw[1:]]
    assert len(terms) == int(raw[0].split()[4]) == int(values['rank'])
    verify(16, terms)
    assert values['exact_rejects'] == '0' and values['producer_state'] == 'stopped', values
    return values

with tempfile.TemporaryDirectory(prefix='metaflip-directed-cli-') as directory:
    root = Path(directory)
    for i, mode in enumerate(('0', 'partners', 'nonbacktracking', 'tabu')):
        state = root/mode
        state.mkdir()
        result = run(mode, state)
        assert result.returncode == 0, result.stdout+result.stderr
        body = check(state)
        assert body['directed_lanes'] == str(int(i>0)), body
        if i>0:
            assert body['directed_mode'] == str(i) and int(body['directed_legal'])>0, body
            assert 1<=int(body['directed_steps'])<=4096
        else:
            assert int(body['cpu_moves']) == 2*4096*3
        before = (state/'checkpoints/gf2/16x16x16/best.txt').read_bytes()
        result = run('bogus', state)
        assert result.returncode == 2 and 'METAFLIP_WIDE_DIRECTED' in result.stdout
        assert (state/'checkpoints/gf2/16x16x16/best.txt').read_bytes() == before
        print('PASS directed CLI', mode, flush=True)
    bounded = root/'bounded'
    bounded.mkdir()
    start = time.monotonic()
    result = run('tabu', bounded, '-J', '1', '--steps', '1000000000', '--rounds', '999', '--secs', '2')
    assert result.returncode == 0 and time.monotonic()-start<10, result.stdout+result.stderr
    body = check(bounded)
    assert body['directed_lanes']=='1' and int(body['cpu_moves'])>0
    print('PASS directed single-worker wall deadline', flush=True)
    for mode in ('0', 'nonbacktracking'):
        state=root/('fleet-'+mode)
        state.mkdir()
        start=time.monotonic()
        result=run(mode,state,'-J','16','--steps','500000','--rounds','999999','--secs','2')
        assert result.returncode==0 and time.monotonic()-start<10, result.stdout+result.stderr
        body=check(state)
        assert body['cpu_lanes']=='16' and int(body['cpu_moves'])>0, body
        assert body['directed_lanes']==str(int(mode!='0')), body
        print('PASS directed 16-worker deadline', mode, body['cpu_moves'], 'attempts', flush=True)
    cycle=root/'cycle'
    cycle.mkdir()
    result=subprocess.run([str(BINARY),'--runtime-root',str(ROOT/'lib/metaflip'),
                           '--state-dir',str(cycle),'--cycle-shapes','8x8,16x16',
                           '--cycle-secs','1','--secs','4','--no-tui','--no-gpu','-J','2'],
                          env=dict(os.environ,METAFLIP_WIDE_DIRECTED='nonbacktracking'),
                          text=True,capture_output=True,timeout=15)
    assert result.returncode==0, result.stdout+result.stderr
    for n in (8,16):
        assert 'metaflip wide: tensor='+str(n)+'x'+str(n) in result.stdout, result.stdout
        lines=(cycle/f'checkpoints/gf2/{n}x{n}x{n}/best.txt').read_text().splitlines()
        verify(n,[tuple(int(v,16) for v in line.split()) for line in lines[1:]])
    assert result.stdout.count('directed_lanes=1 directed_mode=2')>=2, result.stdout
    print('PASS directed bounded shape cycle and exact endpoints', flush=True)
