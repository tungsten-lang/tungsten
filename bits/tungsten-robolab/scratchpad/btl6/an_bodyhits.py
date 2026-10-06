"""Which body parts touch the ball in the flight of each stage's pass, and when (relative to the stage's release and to its table's end): G chain replay."""
import os, pickle, sys, collections
import numpy as np
sys.path.insert(0, "scratchpad/btl6")
import chainrep as C, chainobj as Ob
rec0 = pickle.load(open("out/btl6/recG/rec_84001.pkl", "rb"))
ch = C.Chain("scratchpad/btl5/params/final_g.txt", rec0)
ch.track_body = True
cnt = collections.defaultdict(collections.Counter)
timing = collections.defaultdict(list)
n = 0
for sd in range(84001, 84521):
    rec = pickle.load(open(f"out/btl6/recG/rec_{sd}.pkl", "rb"))
    if not rec["pass_log"] or not rec["pass_log"][0]["ok"]: continue
    st = ch.prep(rec, 2)
    if st is None: continue
    run = ch.run(st)
    if run is None: continue
    n += 1
    rel = run["rel"]; stage = run["stage"]
    for tick, nm in run["body_hits"]:
        # the pass whose flight: the last release at or before the tick
        ks = [s for s in (2, 3, 4) if s in rel and rel[s] <= tick]
        if not ks: continue
        s = max(ks)
        cnt[s][nm] += 1
        end_tab = stage[s]["t0"] + int(np.sum(stage[s]["live"]))
        timing[(s, nm)].append((tick - rel[s], tick - end_tab))
print("starts", n)
for s in sorted(cnt):
    print(f"flight of stage {s}'s ball (contacts after its release): {dict(cnt[s])}")
for (s, nm), v in sorted(timing.items()):
    a = np.array(v)
    if len(a) >= 5:
        print(f"  stage {s} {nm}: n {len(a)} ticks after release: median {np.median(a[:,0]):.0f} (q10 {np.quantile(a[:,0],0.1):.0f}, q90 {np.quantile(a[:,0],0.9):.0f}); relative to the end of the table's program: median {np.median(a[:,1]):.0f}")
