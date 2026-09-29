"""Per-start pass chains and failure reasons by pass index.

    .venv/bin/python scratchpad/btl2/chain.py ctl params s0 s1 secs [overrides] [workers]

For each seed prints the chain of judged passes (ok / why), then a table by pass index
(count, ok, reasons, mean rise apex and horizontal speed at the receiving touch), the
btl streak per start and the mean.  Run from bits/tungsten-robolab.
"""
import collections
import sys

import numpy as np

sys.path.insert(0, "scratchpad/btl2")
from multiprocessing import Pool  # noqa: E402

from common import load, parse_over, run_seed  # noqa: E402


def main():
    ctl, pfile, s0, s1, secs = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5])
    over = sys.argv[6] if len(sys.argv) > 6 else ""
    workers = int(sys.argv[7]) if len(sys.argv) > 7 else 2
    params = load(pfile)
    params.update(parse_over(over))
    with Pool(workers) as p:
        res = p.map(run_seed, [(ctl, params, s, secs) for s in range(s0, s1)])
    by = collections.defaultdict(collections.Counter)
    apex = collections.defaultdict(list)
    vh = collections.defaultdict(list)
    streaks = []
    for r in res:
        log = r["btl_log"]
        pl = r["pass_log"]
        chain = []
        i = 0
        for e in log:
            if e["k"][0] == "D":
                chain.append("d")
                continue
            k = i
            i += 1
            by[k][e["why"] if not e["ok"] else "ok"] += 1
            a = pl[k].get("rise_apex") if k < len(pl) else None
            v = pl[k].get("recv_vh") if k < len(pl) else None
            if a:
                apex[k].append(a)
            if v:
                vh[k].append(v)
            chain.append(("+" if e["ok"] else "-") + (f"{a:.2f}" if a else "?"))
        streaks.append(r["btl_streak"])
        print(r["seed"], "streak", r["btl_streak"], "ok", r["btl_ok"], "/", r["btl_tried"], " ".join(chain[:14]), "|", r.get("lost"))
    for k in sorted(by):
        n = sum(by[k].values())
        ok = by[k]["ok"]
        print(f"pass {k + 1}: n {n} ok {ok} ({100 * ok / n:.0f}%) {dict(by[k])}"
              + (f" apex {np.mean(apex[k]):.2f} vh {np.mean(vh[k]):.2f}" if apex[k] else ""))
    print("streaks", sorted(streaks, reverse=True), "mean", round(float(np.mean(streaks)), 3), "max", max(streaks),
          ">=1:", sum(1 for s in streaks if s >= 1), ">=2:", sum(1 for s in streaks if s >= 2), ">=3:", sum(1 for s in streaks if s >= 3))


if __name__ == "__main__":
    main()
