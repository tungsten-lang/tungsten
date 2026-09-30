"""segstat.py ROWS.jsonl [--thr3 0.005]: per arm, the wrap segments that come within 1e-3 of their tangent in more than thr3 of the control steps of some start
(from segv_near3 where present, else the top-4 'seg_top' entries): how many starts, the worst fraction, and the sum of crossings. The hazard census of a posture."""
import collections, json, sys
import numpy as np
args = sys.argv[1:]
thr3 = 0.005
if "--thr3" in args:
    i = args.index("--thr3"); thr3 = float(args[i + 1]); del args[i:i + 2]
names = json.load(open("/Users/erik/tungsten/bits/tungsten-robolab/out/hazard/seg_names.json"))
rows = {}
for l in open(args[0]):
    try:
        r = json.loads(l)
    except Exception:
        continue
    rows[r["tag"]] = r
arms = collections.OrderedDict()
for t, r in rows.items():
    arms.setdefault(t.split("|")[0], []).append(r)
for arm, rs in arms.items():
    cnt = collections.defaultdict(lambda: [0, 0.0, 0.0])
    used = 0
    for r in rs:
        segs = []
        if r.get("segv_near3"):
            v3 = [float(x) for x in r["segv_near3"].split(",")]
            fl = [float(x) for x in r["segv_flips"].split(",")]
            segs = [(names[j], v3[j], fl[j]) for j in range(len(names)) if v3[j] > thr3]
            used += 1
        else:
            for part in (r.get("seg_top") or "").split(";"):
                if part:
                    nm, f3, f4, fl = part.split(":")
                    if float(f3) > thr3:
                        segs.append((nm, float(f3), float(fl)))
            used += 1
        for nm, f3, fl in segs:
            c = cnt[nm]
            c[0] += 1; c[1] = max(c[1], f3); c[2] += fl
    print(f"== {arm}: {len(rs)} starts; segments with > {thr3:.1%} of steps within 1e-3 in some start:")
    if not cnt:
        print("   none")
    for nm, (n, w, fl) in sorted(cnt.items(), key=lambda x: -x[1][0]):
        print(f"   {nm:44s} in {n:2d} starts, worst {w:.3f}, crossings {int(fl)}")
