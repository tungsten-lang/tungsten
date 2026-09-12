#!/usr/bin/env python3
"""Bounded public wide-square search, independent tensor replay and restart gates."""
from pathlib import Path
from collections import defaultdict
from itertools import product
import os
import subprocess
import tempfile
import time

BINARY = Path(os.environ.get('METAFLIP_TEST_BINARY', Path(__file__).resolve().parents[1] / 'bin/metaflip')).resolve()
RUNTIME = Path(__file__).resolve().parents[1] / 'lib/metaflip'
REFERENCES = dict(zip(range(8, 17), (329, 486, 651, 873, 1068, 1426, 1725, 2058, 2209)))


def read_blob(raw):
    header, *rows = raw.decode().splitlines()
    tag, n, m, p, rank = header.split()
    terms = [tuple(int(v, 16) for v in row.split()) for row in rows]
    assert tag == 'MFW1' and len(terms) == int(rank)
    assert terms == sorted(set(terms)) and all(len(t) == 3 for t in terms)
    return (int(n), int(m), int(p)), terms


def bits(value):
    while value:
        low = value & -value
        yield low.bit_length() - 1
        value ^= low


def exact(shape, terms):
    n, m, p = shape
    fibers = defaultdict(int)
    for u, v, w in terms:
        assert 0 < u < 1 << (n*m) and 0 < v < 1 << (m*p) and 0 < w < 1 << (n*p)
        for a in bits(u):
            for b in bits(v):
                fibers[a, b] ^= w
    for i, j, k in product(range(n), range(m), range(p)):
        fibers[i*m+j, j*p+k] ^= 1 << (i*p+k)
    assert not any(fibers.values())


def fields(path):
    return dict(word.split('=', 1) for word in path.read_text().split() if '=' in word)


def run(*args):
    return subprocess.run([str(BINARY), '--runtime-root', str(RUNTIME), *map(str, args)],
                          text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)


with tempfile.TemporaryDirectory(prefix='metaflip-wide-cli-') as tmp:
    root = Path(tmp)
    for n in range(8, 17):
        case = root / str(n)
        case.mkdir()
        status, best = case / 'status', case / 'best'
        args = ['--tensor', f'{n}x{n}', '--no-tui', '-J', '2', '--steps', '2050',
                '--state-dir', str(case), '--best', str(best), '--status', str(status)]
        result = run(*args, '--rounds', 2)  # default GPU request must not dispatch narrow kernels
        assert result.returncode == 0, result.stdout
        body = fields(status)
        assert body['backend'] == 'packed-cpu' and body['cpu_lanes'] == '2', body
        assert body['gpu_supported'] == '0' and body['gpu_moves'] == '0', body
        assert body['cpu_moves'] == '8200' and body['exact_rejects'] == '0', body
        assert body['producer_state'] == 'stopped', body
        assert int(body['reference_rank']) == REFERENCES[n] and int(body['rank']) <= REFERENCES[n], body
        assert 1 <= int(body['seed_count']) <= 4, body
        if n in (8, 10, 12, 14, 15, 16):
            assert int(body['seed_count']) >= 2, body
        shape, terms = read_blob(best.read_bytes())
        assert shape == (n, n, n) and len(terms) == int(body['rank']) < n**3
        exact(shape, terms)
        before = best.read_bytes()
        # Both ordinary resume and a naive search must preserve a better durable result.
        for extra in ([], ['--naive']):
            result = run(*args, '--rounds', 0, *extra)
            assert result.returncode == 0 and best.read_bytes() == before, result.stdout
        # Explicit canonical MFW1 seeds are accepted; malformed durable data is never overwritten.
        seed = case / 'seed'
        seed.write_bytes(before)
        result = run(*args, '--rounds', 0, '--seed', seed)
        assert result.returncode == 0 and seed.read_bytes() == before, result.stdout
        best.write_text('MFW1 broken\n')
        result = run(*args, '--rounds', 1)
        assert result.returncode == 2 and best.read_text() == 'MFW1 broken\n', result.stdout
        best.write_bytes(before)
        result = run(*args, '--rounds', 1, '--seed', case / 'missing')
        assert result.returncode == 2 and best.read_bytes() == before, result.stdout
        print(f'PASS public {n}x{n}: 2 lanes, {body["seed_count"]} seeds, 8200 flips, exact rank {len(terms)}, restart gates')

    # Exercise every entry in an automatic four-seed bank, not just the
    # first two lanes used above. Imported and composed starts both walk.
    four = root / 'four-seeds'
    four.mkdir()
    result = run('--tensor', '8x8', '-J', 4, '--rounds', 1, '--steps', 2050,
                 '--no-tui', '--no-gpu', '--state-dir', four, '--status', four/'status', '--best', four/'best')
    assert result.returncode == 0, result.stdout
    body = fields(four/'status')
    assert body['cpu_lanes'] == body['seed_count'] == '4' and body['cpu_moves'] == '8200', body
    shape, terms = read_blob((four/'best').read_bytes())
    exact(shape, terms)

    bounded = root / 'bounded'
    started = time.monotonic()
    result = run('--cycle-shapes', '8x8,16x16', '--cycle-secs', 1, '--secs', 3,
                 '--steps', 1000000000, '-J', 2, '--no-tui', '--state-dir', bounded)
    assert result.returncode == 0 and time.monotonic() - started < 15, result.stdout
    for n in (8, 16):
        label = f'{n}x{n}x{n}'
        status = next((bounded / 'runs/gf2' / label).glob('*/status.txt'))
        body = fields(status)
        assert body['cycle_count'] == '2' and body['producer_state'] == 'stopped', body
        assert body['stop_requested'] == '0' and int(body['cpu_moves']) > 0, body
        shape, terms = read_blob((bounded / 'checkpoints/gf2' / label / 'best.txt').read_bytes())
        exact(shape, terms)

    for args in (['--tensor', '17x17'], ['--cycle-shapes', '17x17'],
                 ['--tensor', '8x8', '--gpu-binary', '/unused'],
                 ['--tensor', '8x8', '--record', '1']):
        result = run(*args, '--rounds', 0, '--no-tui', '--state-dir', root / 'invalid')
        assert result.returncode == 2, result.stdout

print('PASS wide-square exact CLI, GPU capability, bounded mixed-width cycle and restart checks')
