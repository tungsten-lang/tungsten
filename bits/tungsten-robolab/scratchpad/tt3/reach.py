"""Which serves does the kinematic paddle (O4) return that no real body could reach? (agent T3) Ball crossing point at the champion's pad plane (plan file p_hit) against the pad positions the champion
actually covered on its hits (sets A and B), and the pelvis travel the serve needs at the champion's own lateral cap (pel_vcap 1.8 m/s)."""
import json, os, sys
import numpy as np
HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground")); sys.path.insert(0, os.path.join(HERE, "scratchpad", "tt3"))
from make_plans import record
rows = {}
for s in "AB":
    for l in open(f"out/tt3/o0_{s}.jsonl"):
        r = json.loads(l); rows[r["seed"]] = r
recs = {sd: record(sd, r) for sd, r in rows.items()}
hit = [sd for sd in rows if recs[sd]["hit"]]
Y = np.array([recs[sd]["p"][1] for sd in rows]); Z = np.array([recs[sd]["p"][2] for sd in rows]); X = np.array([recs[sd]["p"][0] for sd in rows])
Yh = np.array([recs[sd]["p"][1] for sd in hit]); Zh = np.array([recs[sd]["p"][2] for sd in hit])
print(f"ball crossing at the pad plane, all 200 serves: y {Y.min():.2f}..{Y.max():.2f}, z {Z.min():.2f}..{Z.max():.2f}; on the champion's {len(hit)} hits: y {Yh.min():.2f}..{Yh.max():.2f}, z {Zh.min():.2f}..{Zh.max():.2f}")
out_y = [(sd, recs[sd]["p"][1]) for sd in rows if not (Yh.min() - 0.02 <= recs[sd]["p"][1] <= Yh.max() + 0.02)]
out_z = [(sd, recs[sd]["p"][2]) for sd in rows if not (Zh.min() - 0.02 <= recs[sd]["p"][2] <= Zh.max() + 0.02)]
print("serves whose crossing lies outside the champion's covered y range:", len(out_y), "z range:", len(out_z))
# pelvis travel: pelvis y at the start vs the pad y needed
trav = []
for sd in rows:
    z = np.load(f"out/tt3/logs_o0/{sd}.npz"); L = z["L"]
    k = recs[sd]["k"]
    off = L[k, 7 + 1] - L[k, 16 + 1] if recs[sd]["hit"] else 0.2       # pad y - pelvis y at contact
    need = recs[sd]["p"][1] - off - L[0, 16 + 1]
    trav.append((sd, need, recs[sd]["t_hit"]))
T = np.array([[t[1], t[2]] for t in trav])
speed = np.abs(T[:, 0]) * 1.875 / np.maximum(T[:, 1] - 0.1, 0.1)
print(f"pelvis lateral travel the serve asks (ball y - pad offset - start y): median {np.median(np.abs(T[:,0])):.2f} m, 90th pct {np.percentile(np.abs(T[:,0]), 90):.2f} m, max {np.abs(T[:,0]).max():.2f} m; peak speed of a min-jerk slide in the time left after 0.1 s: median {np.median(speed):.2f}, > 1.8 m/s on {int((speed > 1.8).sum())} of 200 serves")
nohit = [sd for sd in rows if not recs[sd]["hit"]]
print("serves the champion never touched:", len(nohit), "of which needing > 1.8 m/s slide:", sum(1 for sd in nohit if speed[list(rows).index(sd)] > 1.8))

# physical bound: the pelvis lateral slide (m 139 kg incl. armature, kp 3500 N/m on a position target limited to +-1 m, joint damping 1000 N s/m) driven flat out toward the serve's crossing:
def t_reach(d, m=139.0, kp=3500.0, c=1000.0, u_max=1.0, dt=0.002):
    x = v = t = 0.0
    u = np.sign(d) * u_max
    while abs(x) < abs(d) and t < 2.0:
        a = (kp * (u - x) - c * v) / m
        v += a * dt; x += v * dt; t += dt
    return t
tr = np.array([t_reach(abs(T[i, 0])) for i in range(len(T))])
avail = T[:, 1] - 0.05       # from 0.05 s (the ball's first frames) to the contact
print(f"flat-out slide time to the crossing vs the time available: infeasible (t_reach > t_hit - 0.05 s) on {int((tr > avail).sum())} of 200 serves; among the 23 never touched by the champion: {sum(1 for i, sd in enumerate(rows) if not recs[sd]['hit'] and tr[i] > avail[i])}")
print("   (the slide only has to bring the pad within the arm's reach of ~0.3 m, so this is conservative by ~0.3 m of travel)")
tr2 = np.array([t_reach(max(abs(T[i, 0]) - 0.3, 0.0)) for i in range(len(T))])
print(f"   with 0.3 m of arm reach credited: infeasible on {int((tr2 > avail).sum())} of 200; of the 23 never touched: {sum(1 for i, sd in enumerate(rows) if not recs[sd]['hit'] and tr2[i] > avail[i])}")
