#!/usr/bin/env python3
"""Parallel directed-walk screen over exact GF(2) seeds. Results append to JSONL.

usage: sweep.py SEEDS.json OUT.jsonl STEPS JOBS [NONCE_BASE] [SHAPE_FILTER_FILE]
Each walker output is fully tensor-checked inside wide-rect-walk before writing.
"""
import concurrent.futures
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import zlib

HERE = Path(__file__).resolve().parent
WALKER = HERE / 'wide-rect-walk'


def run(seed, steps, nonce, outdir):
    out = outdir / f"{seed['shape']}_r{seed['gf2_rank']}_n{nonce}_s{steps}.mfw"
    if out.exists():
        out.unlink()
    proc = subprocess.run([str(WALKER), seed['shape'], seed['mfw'], str(out), str(steps), str(nonce)],
                          capture_output=True, text=True)
    m = re.search(r'seed_rank=(\d+) rank=(\d+) moves=(\d+) accepted=(\d+) no_pair=(\d+) escapes=(\d+)', proc.stdout)
    row = dict(shape=seed['shape'], canonical=seed['canonical'], seed=seed['mfw'], steps=steps, nonce=nonce,
               returncode=proc.returncode)
    if m and proc.returncode == 0:
        row.update(seed_rank=int(m.group(1)), rank=int(m.group(2)), moves=int(m.group(3)),
                   escapes=int(m.group(6)), output=str(out))
    else:
        row['error'] = (proc.stdout + proc.stderr)[-400:]
    return row


def main():
    seeds = json.load(open(sys.argv[1]))
    seeds = seeds['seeds'] if isinstance(seeds, dict) else seeds
    out = Path(sys.argv[2])
    steps, jobs = int(sys.argv[3]), int(sys.argv[4])
    base = int(sys.argv[5]) if len(sys.argv) > 5 else 1
    if len(sys.argv) > 6:
        keep = set(Path(sys.argv[6]).read_text().split())
        seeds = [s for s in seeds if s['shape'] in keep or s['canonical'] in keep]
    outdir = out.parent / (out.stem + '_mfw')
    outdir.mkdir(parents=True, exist_ok=True)
    done = set()
    if out.exists():
        for line in out.read_text().splitlines():
            r = json.loads(line)
            done.add((r['seed'], r['nonce'], r['steps']))
    # Small tensors first: fast feedback.
    seeds = sorted(seeds, key=lambda s: s['gf2_rank'])
    work = []
    repeats = int(os.environ.get('SWEEP_REPEATS', '1'))
    for rep in range(repeats):
        for s in seeds:
            nonce = base + rep * 7919 + zlib.crc32(s['shape'].encode()) % 1000003
            if (s['mfw'], nonce, steps) not in done:
                work.append((s, nonce))
    print(f'{len(work)} walks queued', flush=True)
    with open(out, 'a') as log, concurrent.futures.ThreadPoolExecutor(jobs) as pool:
        futs = [pool.submit(run, s, steps, nonce, outdir) for s, nonce in work]
        for fut in concurrent.futures.as_completed(futs):
            row = fut.result()
            log.write(json.dumps(row) + '\n')
            log.flush()
            if row.get('rank') is not None and row['rank'] < row['seed_rank']:
                print('DROP', row['shape'], row['seed_rank'], '->', row['rank'], flush=True)
            elif 'error' in row:
                print('ERROR', row['shape'], row['error'][-200:], flush=True)


if __name__ == '__main__':
    main()
