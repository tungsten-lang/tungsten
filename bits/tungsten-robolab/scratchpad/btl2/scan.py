"""Grid of parameter overrides over seeds: pass-by-pass results.

    .venv/bin/python scratchpad/btl2/scan.py ctl params '{"bl_drv":[1,2],"bl_dzc":[0.05,0.15]}' s0 s1 secs [workers]

Prints one row per combination: ok counts of pass 1..4 (complete BTLs), the mean rise apex of pass 1..3,
the streak mean / max, and the counts of starts with streak >= 1, 2, 3.  Rows sorted by streak mean.
"""
import itertools
import json
import sys

import numpy as np

sys.path.insert(0, "scratchpad/btl2")
from multiprocessing import Pool  # noqa: E402

from common import load, run_seed  # noqa: E402


def job_of(job):
    tag, args = job
    r = run_seed(args)
    return tag, r


def summarize(rs):
    okk = [0, 0, 0, 0]
    apex = [[], [], []]
    st = []
    for r in rs:
        pl = r["pass_log"]
        for k in range(4):
            if len(pl) > k and pl[k]["ok"]:
                okk[k] += 1
        for k in range(3):
            if len(pl) > k and pl[k].get("rise_apex"):
                apex[k].append(pl[k]["rise_apex"])
        st.append(r["btl_streak"])
    st = np.array(st)
    return okk, [float(np.mean(a)) if a else 0.0 for a in apex], st


def main():
    ctl, pfile, spec = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
    # seeds: "s0 s1" (a range) or a comma list in argv[4] with argv[5] = "-"
    if "," in sys.argv[4]:
        seeds = [int(x) for x in sys.argv[4].split(",")]
    else:
        seeds = list(range(int(sys.argv[4]), int(sys.argv[5])))
    secs = float(sys.argv[6])
    workers = int(sys.argv[7]) if len(sys.argv) > 7 else 2
    base = load(pfile)
    keys = list(spec)
    combos = list(itertools.product(*[spec[k] for k in keys]))
    jobs = []
    for c in combos:
        p = dict(base)
        p.update(dict(zip(keys, c)))
        for s in seeds:
            jobs.append((c, (ctl, p, s, secs)))
    with Pool(workers) as pool:
        res = pool.map(job_of, jobs)
    rows = []
    for c in combos:
        rs = [r for tag, r in res if tag == c]
        okk, apex, st = summarize(rs)
        rows.append((float(st.mean()), c, okk, apex, st))
    rows.sort(key=lambda r: -r[0])
    print("keys", keys, "seeds", seeds[0], "..", seeds[-1], len(seeds), "secs", secs)
    for mean, c, okk, apex, st in rows:
        print(f"streak mean {mean:.2f} max {st.max()} >=1 {int((st >= 1).sum())} >=2 {int((st >= 2).sum())} >=3 {int((st >= 3).sum())} | "
              f"ok1-4 {okk} | apex {' '.join(f'{a:.2f}' for a in apex)} | {c}")


if __name__ == "__main__":
    main()
