import glob, json, sys, collections
import numpy as np
sys.path.insert(0, "scratchpad/btl3")
import dlib, m1_analyze as A
rows = {r["seed"]: r for r in np.load("out/btl4/an_stage2_rows.npy", allow_pickle=True)}
tab = collections.defaultdict(collections.Counter)
for fn in sorted(glob.glob("out/btl4/live_base/live_*.npz")):
    z = np.load(fn)
    seed = int(fn.split("_")[-1].split(".")[0])
    ws = A.stage_windows(z)
    if len(ws) < 3 or seed not in rows:
        continue
    rec2 = A.extract(z, "r", ws[2][1])
    if rec2 is None or "rel_v" not in rec2:
        continue
    nx = dlib.next_input(z, rec2["kr"])
    if nx is None:
        continue
    w = z["q_l"][nx["k"] - 1][4]
    pl = json.loads(str(z["pass_log"]))
    p4 = "p4ok" if (len(pl) > 3 and pl[3]["ok"]) else ("p4fail" if len(pl) > 3 else "nop4")
    grp = "ready(wr>=0.7)" if w >= 0.7 else "off(wr<0.7)"
    tab[grp][rows[seed]["cat"] + "/" + p4] += 1
for g, c in tab.items():
    print(g, sum(c.values()), dict(c))
