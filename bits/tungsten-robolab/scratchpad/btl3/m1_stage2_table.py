import sys, json, glob
import numpy as np
sys.path.insert(0, "scratchpad/btl3")
import m1_analyze as A
d = sys.argv[1]; stage = int(sys.argv[2])
rows = []
for fn in sorted(glob.glob(d + "/live_*.npz")):
    z = np.load(fn)
    pl = json.loads(str(z["pass_log"]))
    ws = A.stage_windows(z)
    if len(ws) <= stage: continue
    side, k0 = ws[stage]
    rec = A.extract(z, side, k0)
    if rec is None or "rel_v" not in rec: continue
    a = A.arrival(z, rec["kr"])
    e = pl[stage] if stage < len(pl) else {}
    seed = int(fn.split("_")[-1].split(".")[0])
    rows.append((seed, rec, a, e))
print("seed  touch_ms dur_ms | rel_v (vx vy vz) |v| | touch palm-ball off (x y z) | palm v (x y z) | pcx pcy | arrive apex | gate body outcome ok")
for seed, rec, a, e in rows[:70]:
    t = rec["touch"]
    print(f"{seed} {t['t']*1000:4.0f} {t['dur']*1000:3.0f} | {rec['rel_v'][0]:+.2f} {rec['rel_v'][1]:+.2f} {rec['rel_v'][2]:+.2f} {np.linalg.norm(rec['rel_v']):.2f} | "
          f"{t['palm'][0]:+.3f} {t['palm'][1]:+.3f} {t['palm'][2]:+.3f} | {t['pv'][0]:+.2f} {t['pv'][1]:+.2f} {t['pv'][2]:+.2f} | {rec['pc'][0]:+.2f} {rec['pc'][1]:+.2f} | "
          f"{('%+.2f %+.2f' % tuple(a[0])) if a else '   none    '} {('%.2f' % a[1]) if a else ' -  '} | {e.get('gate')} {e.get('body')} {e.get('outcome')} {e.get('ok')}")
