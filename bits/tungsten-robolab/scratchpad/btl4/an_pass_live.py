import glob, json, sys, collections
import numpy as np
d = sys.argv[1]
cat = {k: collections.Counter() for k in (2, 3, 4, 5)}
for fn in sorted(glob.glob(d + "/live_*.npz")):
    z = np.load(fn)
    pl = json.loads(str(z["pass_log"]))
    for k in (2, 3, 4, 5):
        if len(pl) < k:
            continue
        if k > 2 and not pl[k - 2]["ok"]:
            continue          # the previous pass must be ok
        e = pl[k - 1]
        if e["ok"]: c = "ok"
        elif not e["released"]: c = "not released"
        elif not e["gate"]: c = "no gate"
        elif e["body"]: c = "body"
        else: c = "gate ok, then " + str(e["outcome"])
        cat[k][c] += 1
for k in (2, 3, 4, 5):
    n = sum(cat[k].values())
    print(f"pass {k} (given pass {k-1} ok): n {n}", {c: v for c, v in cat[k].most_common()})
