"""First body part to touch the ball in the flight of each stage's pass (from the release to the receiving hand's first touch), G chain replay, with timing."""
import os, pickle, sys, collections
import numpy as np
sys.path.insert(0, "scratchpad/btl6")
import chainrep as C
rec0 = pickle.load(open("out/btl6/recG/rec_84001.pkl", "rb"))
ch = C.Chain("scratchpad/btl5/params/final_g.txt", rec0)
ch.track_body = True
first = collections.defaultdict(collections.Counter)
tim = collections.defaultdict(list)
nst = collections.Counter()
for sd in range(84001, 84841):
    rec = pickle.load(open(f"out/btl6/recG/rec_{sd}.pkl", "rb"))
    if not rec["pass_log"] or not rec["pass_log"][0]["ok"]: continue
    st = ch.prep(rec, 2)
    if st is None: continue
    run = ch.run(st)
    if run is None: continue
    rel = run["rel"]; cf = run["out"]["cf"]; n = run["n"]
    for s in (2, 3, 4):
        if s not in rel: continue
        nst[s] += 1
        hand_next = 0 if C.HAND[s] == "r" else 1       # the receiving hand's column in cf (0 left, 1 right)
        r = rel[s]
        tt = np.nonzero(cf[r + 2:, hand_next] > 0.3)[0]
        end = (r + 2 + tt[0]) if len(tt) else min(n, r + 80)
        hits = [(t, nm) for t, nm in run["body_hits"] if r < t <= end]
        # exclude the pushing arm contacts within 3 ticks of the release (its own chatter)
        if hits:
            t, nm = hits[0]
            first[s][nm] += 1
            tim[(s, nm)].append(t - r)
        else:
            first[s]["none"] += 1
for s in (2, 3, 4):
    print(f"stage {s}'s pass ({nst[s]} starts released): first body contact {dict(first[s])}")
    for nm in first[s]:
        if nm != "none" and first[s][nm] >= 5:
            a = np.array(tim[(s, nm)])
            print(f"     {nm}: ticks after release median {np.median(a):.0f} q10 {np.quantile(a,0.1):.0f} q90 {np.quantile(a,0.9):.0f}")
