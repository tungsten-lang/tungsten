"""Summaries of out/btl5/stage_info.pkl (an5_stage.py): per stage, how many starts have a trigger, the schedule features' spread, and the pass outcome
by feature tercile.   scratchpad/btl5/py scratchpad/btl5/an5_report.py out/btl5/stage_info.pkl"""
import pickle
import sys

import numpy as np

res = pickle.load(open(sys.argv[1], "rb"))
print("starts", len(res), "mean streak", np.mean([r["streak"] for r in res]))
npass = 5
for k in range(npass):
    n = sum(1 for r in res if len(r["pass_log"]) > k and r["pass_log"][k]["outcome"] is not None)
    ok = sum(1 for r in res if len(r["pass_log"]) > k and r["pass_ok"][k])
    print(f"pass {k + 1}: judged {n} ok {ok} ({100 * ok / max(n, 1):.0f}%)")
for st in range(5):
    rows = [r for r in res if st in r["stages"]]
    print(f"\nstage {st}: {len(rows)} starts with a trigger")
    if not rows:
        continue
    A = np.array([[r["stages"][st]["x"], r["stages"][st]["y"], r["stages"][st]["t"], r["stages"][st]["vzc"]] + r["stages"][st]["post"] for r in rows])
    names = ["x", "y", "t", "vzc", "wflex", "sabd", "elbow"]
    for i, nm in enumerate(names):
        print(f"  {nm}: mean {A[:, i].mean():+.3f} sd {A[:, i].std():.3f} q10 {np.quantile(A[:, i], 0.1):+.3f} q50 {np.quantile(A[:, i], 0.5):+.3f} q90 {np.quantile(A[:, i], 0.9):+.3f}")
    # the pass this stage makes is pass index st (0-based): outcome by prior pass ok
    if st >= 1:
        okprev = [r for r in rows if all(r["pass_ok"][:st]) and len(r["pass_log"]) > st]
        print(f"  with passes 1..{st} judged ok: {len(okprev)}: stage pass ok {sum(1 for r in okprev if r['pass_ok'][st])}")
        if okprev:
            B = np.array([[r["stages"][st]["x"], r["stages"][st]["y"], r["stages"][st]["t"], r["stages"][st]["vzc"]] + r["stages"][st]["post"] for r in okprev])
            for i, nm in enumerate(names):
                print(f"    {nm}: mean {B[:, i].mean():+.3f} sd {B[:, i].std():.3f}")
