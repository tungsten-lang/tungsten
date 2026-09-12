#!/usr/bin/env python3
"""Bounded single-worker, counterbalanced directed ablation; no live-state writes."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from import_wide_seeds import verify, blob

def check(path, n):
    raw = path.read_bytes()
    header, *lines = raw.decode().splitlines()
    parts = header.split()
    assert parts[:4] == ['MFW1', str(n), str(n), str(n)]
    terms = [tuple(int(v, 16) for v in row.split()) for row in lines]
    assert len(terms) == int(parts[4]) and all(len(t) == 3 for t in terms)
    assert terms == sorted(set(terms))
    verify(n, terms)
    assert raw == blob(n, terms)
    return raw

def run(binary, output, milliseconds):
    output.mkdir(parents=True, exist_ok=False)
    rows = []
    with (output/'results.jsonl').open('w') as log:
        for n in (8, 12, 15, 16):
            for seed in (19071, 19072):
                for repeat, order in enumerate(((0, 1, 2, 3), (3, 2, 1, 0))):
                    for mode in order:
                        stem = output/f'{n}-{seed}-{repeat}-{mode}'
                        start = time.monotonic()
                        try:
                            proc = subprocess.run([str(binary), str(n), str(mode), str(seed), str(milliseconds), str(stem)],
                                                  capture_output=True, text=True, timeout=30)
                        except subprocess.TimeoutExpired as exc:
                            def decoded(value):
                                return value.decode(errors='replace') if isinstance(value, bytes) else value or ''
                            log.write(json.dumps(dict(n=n, seed=seed, repeat=repeat, mode=mode,
                                                      timeout=True, wall_seconds=time.monotonic()-start,
                                                      stdout=decoded(exc.stdout), stderr=decoded(exc.stderr)))+'\n')
                            log.flush()
                            raise
                        raw = dict(n=n, seed=seed, repeat=repeat, mode=mode, exit=proc.returncode,
                                   wall_seconds=time.monotonic()-start, stdout=proc.stdout, stderr=proc.stderr)
                        log.write(json.dumps(raw)+'\n')
                        log.flush()
                        assert proc.returncode == 0, raw
                        result = next(line for line in proc.stdout.splitlines() if line.startswith('RESULT '))
                        row = {k: int(v) for k,v in (item.split('=') for item in result.split()[1:])}
                        samples = [check(stem.with_name(stem.name+f'-{i}.mfw'), n) for i in range(row['samples'])]
                        check(stem.with_name(stem.name+'-best.mfw'), n)
                        row.update(repeat=repeat, exact_unique_samples=len(set(samples)),
                                   endpoint_transition_fraction=sum(a!=b for a,b in zip(samples,samples[1:]))/max(1,len(samples)-1))
                        rows.append(row)
                        log.write(json.dumps(dict(checked=row))+'\n')
                        log.flush()
                        print(json.dumps(row), flush=True)
    (output/'summary.json').write_text(json.dumps(rows, indent=2)+'\n')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--milliseconds', type=int, default=1000)
    args = parser.parse_args()
    run(args.binary.resolve(), args.output.resolve(), args.milliseconds)
