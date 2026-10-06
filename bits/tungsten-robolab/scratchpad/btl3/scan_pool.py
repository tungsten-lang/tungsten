"""Scan param overrides on pooled seed sets with chain.py; paired statistics against the first config.

    OMP_NUM_THREADS=1 nohup nice -n 10 .venv/bin/python scratchpad/btl3/scan_pool.py ctl params "2001:2129,5001:5129" secs workers tag "ov0;ov1;..." [params2=ov index file] > out/btl3/pool_<tag>.log &

Config 0 is the reference (usually ""). Every config runs on every seed range (chain.py, `workers` workers); one line per config:
  tag i | override | pooled mean (se) | per-set means | paired diff vs config 0 (se) | per-pass ok/n (pooled) | >=2 >=3 >=4
Per-start streaks go to out/btl3/pool_<tag>_<i>.streaks ("seed streak" lines).
An override may start with "@file:" to use another params file for that config (then "ov" after a '|').
"""
import re
import subprocess
import sys

import numpy as np


def run(ctl, params, s0, s1, secs, ov, workers):
    out = subprocess.run([sys.executable, "scratchpad/btl2/chain.py", ctl, params, str(s0), str(s1), str(secs), ov, str(workers)],
                         capture_output=True, text=True).stdout
    starts = re.findall(r"^(\d+) streak (\d+)", out, flags=re.M)
    passes = re.findall(r"^pass (\d): n (\d+) ok (\d+)", out, flags=re.M)
    return [(int(a), int(b)) for a, b in starts], [(int(k), int(n), int(ok)) for k, n, ok in passes]


def main():
    ctl, params, sets, secs, workers, tag, ovs = sys.argv[1:8]
    ranges = [tuple(int(v) for v in r.split(":")) for r in sets.split(",")]
    ref = None
    for i, ov in enumerate(ovs.split(";")):
        p = params
        if ov.startswith("@"):
            p, _, ov = ov[1:].partition("|")
        allst, allp = [], {}
        per = []
        for (s0, s1) in ranges:
            st, ps = run(ctl, p, s0, s1, secs, ov, workers)
            allst += st
            per.append(np.mean([b for a, b in st]) if st else float("nan"))
            for k, n, ok in ps:
                a = allp.setdefault(k, [0, 0])
                a[0] += n
                a[1] += ok
        with open(f"out/btl3/pool_{tag}_{i}.streaks", "w") as f:
            f.write("\n".join(f"{a} {b}" for a, b in allst) + "\n")
        arr = np.array([b for a, b in allst], float)
        line = f"{tag} {i} | {ov or '-'} | mean {arr.mean():.3f} (se {arr.std(ddof=1) / np.sqrt(len(arr)):.3f}) | sets " + " ".join(f"{m:.3f}" for m in per)
        if ref is None:
            ref = arr
        elif len(ref) == len(arr):
            d = arr - ref
            line += f" | paired {d.mean():+.3f} (se {d.std(ddof=1) / np.sqrt(len(d)):.3f})"
        line += " | " + " ".join(f"p{k}:{a[1]}/{a[0]}" for k, a in sorted(allp.items())[:4])
        line += f" | >=2 {int((arr >= 2).sum())} >=3 {int((arr >= 3).sum())} >=4 {int((arr >= 4).sum())}"
        print(line, flush=True)


if __name__ == "__main__":
    main()
