#!/usr/bin/env python3
"""Screen one-coordinate projections (13 basis modes) of exact parents.

usage: project_screen.py SEEDS.json OUT.jsonl JOBS
Keeps, per child shape, the lowest-rank exact projection (written as MFW1 under
proj_mfw/). A child is interesting if it beats our scoreboard for its shape.
"""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
TOOLS = Path('/Users/erik/tungsten-mf-ternary/bits/tungsten-metaflip/tools')
sys.path.insert(0, str(TOOLS))


def lille():
    sys.path.insert(0, str(HERE))
    import pub
    return pub.tables()[1]  # best listed rank in any ring


def work(seed):
    import screen_top_two_projection_children as top
    from search_wide_projection_walks import proposals
    public = lille()
    import gf2_record_board as grb
    path = Path(seed['mfw'])
    shape, terms = grb.decode(path, grb.load(path))  # MFW1, .gz.b64 or decimal text; exact-checked
    raw = top.blob(shape, terms)
    rows = proposals(tuple(shape), terms, public, per_shape=1)
    out = []
    outdir = HERE / 'proj_mfw'
    for row in rows:
        top.exact(row['shape'], row['terms'])  # independent re-check before retention
        name = f"{'x'.join(map(str, row['shape']))}_r{row['rank']}_{row['sha256'][:10]}.mfw"
        path = outdir / name
        if not path.exists():
            path.write_bytes(row['raw'])
        out.append(dict(parent=seed['mfw'], parent_sha256=hashlib.sha256(raw).hexdigest(), parent_rank=len(terms), shape='x'.join(map(str, row['shape'])),
                        rank=row['rank'], mode=row['mode'], axis=row['axis'], coordinate=row['coordinate'],
                        lille=row['public_rank'], mfw=str(path)))
    return out


def main():
    seeds = json.load(open(sys.argv[1]))
    seeds = seeds['seeds'] if isinstance(seeds, dict) else seeds
    out = Path(sys.argv[2])
    jobs = int(sys.argv[3])
    (HERE / 'proj_mfw').mkdir(exist_ok=True)
    done = set()
    if out.exists():
        done = {json.loads(l)['parent'] for l in out.read_text().splitlines()}
    todo = [s for s in seeds if s['mfw'] not in done]
    print(len(todo), 'parents', flush=True)
    with open(out, 'a') as log, concurrent.futures.ProcessPoolExecutor(jobs) as pool:
        futs = {pool.submit(work, s): s for s in todo}
        for fut in concurrent.futures.as_completed(futs):
            try:
                rows = fut.result()
            except Exception as exc:
                print('ERROR', futs[fut]['mfw'], repr(exc), flush=True)
                continue
            if not rows:
                rows = [dict(parent=futs[fut]['mfw'], shape=None)]
            for r in rows:
                log.write(json.dumps(r) + '\n')
            log.flush()
            best = [r for r in rows if r.get('shape') and r['rank'] < r['lille']]
            for r in best:
                print('CHILD-BELOW-LILLE', r['shape'], r['rank'], 'lille', r['lille'], flush=True)


if __name__ == '__main__':
    main()
