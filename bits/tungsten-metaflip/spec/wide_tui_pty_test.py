#!/usr/bin/env python3
"""Exercise actual styled terminal frames, resize and q on both backends."""
import argparse
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import tempfile
import termios
import time
import unicodedata

FRAME = re.compile(rb'\x1b\[\?2026h\x1b\[H(.*?)\x1b\[J\x1b\[\?2026l', re.S)
SGR = re.compile(r'\x1b\[[0-9;]*m')


def rows(frame):
    return [row.removesuffix('\x1b[K') for row in frame.decode().replace('\r', '').splitlines()]


def plain(frame):
    return [SGR.sub('', row) for row in rows(frame)]


def columns(text):
    return sum(0 if unicodedata.combining(c) else 2 if unicodedata.east_asian_width(c) in 'WF' else 1 for c in text)


def capture(binary, runtime, root, shape, report):
    case = root / shape
    pid, master = pty.fork()
    if pid == 0:
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack('HHHH', 60, 120, 0, 0))
        os.execv(str(binary), [str(binary), '--runtime-root', str(runtime), '--tensor', shape,
                              '--state-dir', str(case), '--tui', '--secs', '12', '-J', '2',
                              '--steps', '100000', '--no-gpu'])
    data = bytearray()
    resized_at = 0
    done = False
    sent = False
    deadline = time.monotonic() + 25
    try:
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    data.extend(os.read(master, 65536))
                except OSError:
                    pass
            frames = FRAME.findall(data)
            if shape == '3x3':
                if len(frames) >= 2 and not sent:
                    os.write(master, b'q')
                    sent = True
            else:
                if len(frames) >= 3 and not resized_at:
                    resized_at = len(frames)
                    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', 60, 80, 0, 0))
                    os.kill(pid, signal.SIGWINCH)
                if resized_at and len(frames) >= resized_at + 2 and not sent:
                    os.write(master, b'q')
                    sent = True
            waited, code = os.waitpid(pid, os.WNOHANG)
            if waited:
                done = True
                assert os.waitstatus_to_exitcode(code) == 0, data[-6000:].decode(errors='replace')
                break
        assert sent and done, data[-6000:].decode(errors='replace')
        frames = FRAME.findall(data)
        frame = frames[1]
        text = '\n'.join(plain(frame))
        assert b'\x1b[1;33mmetaflip\x1b[0m' in frame
        assert 'GF(2)' in text and 'density' in text and 'moves' in text and 'elapsed' in text
        assert all(title in text for title in ('CPU islands', 'Diversity', 'Effectiveness', 'Rank timeline'))
        assert re.search(r'^  w00 .*\d(?:\.\d)?[KMB]?/s', text, re.M), text
        assert re.search(r'^  w01 .*\d(?:\.\d)?[KMB]?/s', text, re.M), text
        if shape != '3x3':
            assert 'snapshot age' in text and 'GPU unavailable' in text
            assert 'world record' not in text and 'WR ' not in text
            assert 'space=reset' not in text and 'w=reseed' not in text
            assert 'rank    ' in text and 'density ' in text
            if shape == '16x16':
                assert re.search(r'walk\s+r\d{4}/r\d{4}\s+', text), text
            for i, candidate in enumerate(frames):
                width = 120 if i < resized_at else 80
                for row in plain(candidate):
                    assert columns(row) <= width, (shape, width, columns(row), row)
            status = next((case / 'runs/gf2' / (shape + 'x' + shape.split('x')[0])).glob('*/status.txt'))
            fields = dict(word.split('=', 1) for word in status.read_text().split() if '=' in word)
            assert fields['stop_requested'] == '1' and fields['exact_rejects'] == '0', fields
            assert int(fields['cpu_moves']) > 0 and fields['producer_state'] == 'stopped', fields
        if report:
            report.mkdir(parents=True, exist_ok=True)
            (report / (shape + '.ansi')).write_bytes(data)
            (report / (shape + '-120.frame')).write_bytes(frame)
            (report / (shape + '-120.txt')).write_text(text + '\n')
            if resized_at:
                (report / (shape + '-80.frame')).write_bytes(frames[-1])
                (report / (shape + '-80.txt')).write_text('\n'.join(plain(frames[-1])) + '\n')
        print(f'PASS {shape} real TUI: styling, worker rates, sections, resize and q')
    finally:
        if not done:
            os.killpg(pid, signal.SIGTERM)
            try:
                os.killpg(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)
        os.close(master)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('binary', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    runtime = Path(__file__).resolve().parents[1] / 'lib/metaflip'
    with tempfile.TemporaryDirectory(prefix='metaflip-wide-tui-') as tmp:
        for shape in ('3x3', '8x8', '16x16'):
            capture(args.binary.resolve(), runtime, Path(tmp), shape, args.report)
