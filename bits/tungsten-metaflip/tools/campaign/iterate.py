#!/usr/bin/env python3
"""Iterative deepening: walk each shape's current best until `patience` rounds stall.

usage: iterate.py SEEDS.json OUT.jsonl STEPS WALKS_PER_ROUND PATIENCE JOBS NONCE_BASE
Rows log parent/child SHA-256 so every retained state has a replayable lineage.
"""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import threading

HERE = Path(__file__).resolve().parent
WALKER = HERE / 'wide-rect-walk'
RESULT = re.compile(r'seed_rank=(\d+) rank=(\d+) moves=(\d+)')


def walk(shape, seed, steps, nonce, outdir):
    out = outdir / f'{shape}_n{nonce}_s{steps}.mfw'
    if out.exists():
        out.unlink()
    proc = subprocess.run([str(WALKER), shape, str(seed), str(out), str(steps), str(nonce)],
                          capture_output=True, text=True)
    m = RESULT.search(proc.stdout)
    if proc.returncode or not m:
        return None, (proc.stdout + proc.stderr)[-300:]
    return (int(m.group(2)), out), None


def main():
    seeds = json.load(open(sys.argv[1]))
    log = Path(sys.argv[2])
    steps, per_round, patience, jobs, base = map(int, sys.argv[3:8])
    outdir = log.parent / (log.stem + '_mfw')
    outdir.mkdir(exist_ok=True)
    lock = threading.Lock()
    pool = concurrent.futures.ThreadPoolExecutor(jobs)

    def shape_task(index, seed):
        best_rank, best_path = seed['gf2_rank'], Path(seed['mfw'])
        stall, round_no = 0, 0
        while stall < patience:
            nonces = [base + 100003 * index + 7919 * (round_no * per_round + k) for k in range(per_round)]
            futures = [pool.submit(walk, seed['shape'], best_path, steps, n, outdir) for n in nonces]
            for nonce, fut in zip(nonces, futures):
                result, error = fut.result()
                row = dict(shape=seed['shape'], canonical=seed['canonical'], round=round_no, nonce=nonce,
                           steps=steps, parent=str(best_path),
                           parent_sha256=hashlib.sha256(best_path.read_bytes()).hexdigest())
                if result is None:
                    row['error'] = error
                else:
                    rank, path = result
                    row.update(parent_rank=best_rank, rank=rank, output=str(path),
                               sha256=hashlib.sha256(path.read_bytes()).hexdigest())
                with lock:
                    log.open('a').write(json.dumps(row) + '\n')
            # adopt the lowest rank of the round
            ranks = [f.result()[0] for f in futures if f.result()[0]]
            low = min(ranks, key=lambda r: r[0]) if ranks else None
            if low and low[0] < best_rank:
                with lock:
                    print('DROP', seed['shape'], best_rank, '->', low[0], flush=True)
                best_rank, best_path = low
                stall = 0
            else:
                stall += 1
            round_no += 1
        with lock:
            print('DONE', seed['shape'], best_rank, flush=True)
        return seed['shape'], best_rank

    # One coordinator thread per shape; walks share the bounded pool.
    with concurrent.futures.ThreadPoolExecutor(len(seeds)) as coord:
        list(coord.map(lambda a: shape_task(*a), enumerate(seeds)))
    pool.shutdown()


if __name__ == '__main__':
    main()
