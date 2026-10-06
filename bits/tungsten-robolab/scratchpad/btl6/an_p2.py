"""Failure anatomy of pass 2 (the left return, judged with the right hand's reception) and pass 3 on D4's G-chain records (rec_f, 840 starts; analysis only)."""
import os, pickle, sys, collections
import numpy as np
D = "out/btl5/rec_f"
rows = []
for f in sorted(os.listdir(D))[:840]:
    r = pickle.load(open(os.path.join(D, f), "rb"))
    lab = r["labels"]
    pl = r["pass_log"]
    # onsets of g_run per hand
    def onsets(hand, name):
        out = []
        prev = False
        for k, l in enumerate(lab):
            cur = f"{hand}:{name}" in l
            if cur and not prev:
                out.append(k)
            prev = cur
        return out
    gr = onsets("right", "g_run"); gl = onsets("left", "g_run")
    xr = onsets("right", "x_recover"); xl = onsets("left", "x_recover")
    rows.append((r["seed"], r["streak"], [(p["k"], p["ok"], p["outcome"], p["gate"], p["body"], p.get("rise_apex")) for p in pl[:6]], gr, gl, xr, xl))
# pass 2 failures
c2 = collections.Counter()
for seed, st, pl, gr, gl, xr, xl in rows:
    if len(pl) >= 2 and pl[0][1]:
        p = pl[1]
        if p[1]:
            c2["ok"] += 1
        else:
            # did stage 2 (right table, 2nd g_run) trigger?
            trig = len(gr) >= 2
            c2[("fail", "outcome=" + str(p[2]), "gate" if p[3] else "nogate", "body" if p[4] else "nobody", "stage2trig" if trig else "NOtrig")] += 1
for k, v in sorted(c2.items(), key=lambda kv: -kv[1]):
    print(v, k)
print("---- pass 3 failures given pass 2 ok")
c3 = collections.Counter()
for seed, st, pl, gr, gl, xr, xl in rows:
    if len(pl) >= 3 and pl[0][1] and pl[1][1]:
        p = pl[2]
        if p[1]:
            c3["ok"] += 1
        else:
            trig = len(gl) >= 2
            c3[("fail", "outcome=" + str(p[2]), "gate" if p[3] else "nogate", "body" if p[4] else "nobody", "stage3trig" if trig else "NOtrig")] += 1
for k, v in sorted(c3.items(), key=lambda kv: -kv[1]):
    print(v, k)
