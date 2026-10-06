"""Stage-2 contact for weak vs strong incoming balls (G chain replay): ball height and speed at the first right-hand touch, palm speed, release velocity, delivered apex."""
import os, pickle, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl6")
import chainrep as C, chainobj as Ob
rec0 = pickle.load(open("out/btl6/recG/rec_84001.pkl", "rb"))
ch = C.Chain("scratchpad/btl5/params/final_g.txt", rec0)
rows = []
for sd in range(84001, 84401):
    rec = pickle.load(open(f"out/btl6/recG/rec_{sd}.pkl", "rb"))
    if not rec["pass_log"] or not rec["pass_log"][0]["ok"]: continue
    st = ch.prep(rec, 2)
    if st is None: continue
    v0 = ch.vzc0(st)
    if v0 is None: continue
    run = ch.run(st, upto=2)
    if run is None: continue
    o = run["out"]; cf = o["cf"]; pos = o["pos"]; vel = o["vel"]; palm = o["palm"]
    t = np.nonzero(cf[:, 1] > 0.3)[0]
    if len(t) == 0:
        rows.append((v0, None)); continue
    f = t[0]
    # release: last right contact before the floor contact
    fl = np.nonzero(cf[f:, 2] > 0.2)[0]
    if len(fl) == 0:
        rows.append((v0, None)); continue
    b = f + fl[0]
    seg = t[t < b]; rel = seg[-1]
    ps = (palm[f + 1, 1] - palm[f - 1, 1]) / 0.01
    rows.append((v0, dict(zc=pos[f, 2], vzc=vel[f, 2], palm_v=np.linalg.norm(ps), palm_vz=ps[2], tf=f * 0.005, rv=vel[rel], dur=(rel - f) * 0.005, nt=len(seg))))
def grp(lo, hi):
    sel = [r[1] for r in rows if lo <= r[0] < hi and r[1] is not None]
    miss = sum(1 for r in rows if lo <= r[0] < hi and r[1] is None)
    if not sel: return f"vzc0 {lo}-{hi}: n 0, miss {miss}"
    g = lambda k: np.mean([s[k] for s in sel], axis=0)
    return (f"vzc0 {lo}-{hi}: n {len(sel)} (no touch/bounce {miss}) ball z at contact {g('zc'):.3f} vz {g('vzc'):+.2f} | palm speed {g('palm_v'):.2f} vz {g('palm_vz'):+.2f} | touch tick {g('tf'):.3f} s | contact {g('dur')*1000:.0f} ms | release v {np.round(g('rv'),2).tolist()}")
for lo, hi in [(0, 0.5), (0.5, 1.0), (1.0, 1.3), (1.3, 1.6), (1.6, 3)]:
    print(grp(lo, hi))
