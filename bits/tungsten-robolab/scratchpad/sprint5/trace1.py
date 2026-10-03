"""trace1.py PARAMS CONTROLLER SEED SECONDS [t0 t1] [--every 0.05]: chunk label, torso pitch, COM - feet, speed, contact flags of one standing-start rollout (beyond body)."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["ROBOLAB_CALIB"] = "v4"; os.environ["ROBOLAB_PROFILE"] = "beyond"; os.environ["ROBOLAB_PROFILE_PARTS"] = "strength,speed,tendon,activation"
sys.path.insert(0, os.path.join(ROOT, "playground"))
import math
from practice import load_task, read_params
from bridge import Sim
params, ctl, seed, secs = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4])
t0 = float(sys.argv[5]) if len(sys.argv) > 5 else 0.0
t1 = float(sys.argv[6]) if len(sys.argv) > 6 else secs
every = 0.05
class R:
    def __init__(s): s.nx = 0.0; s.rows = []
    def maybe_capture(s, sim):
        d = sim.d
        if d.time < s.nx: return
        s.nx = d.time + every
        import mujoco
        pid = sim.m.body("pelvis").id; tid = sim.m.body("torso").id
        tu = d.xmat[tid].reshape(3, 3)[:, 2]
        ct = sim.contacts()
        fx = 0.5 * (float(d.body("l_foot").xpos[0]) + float(d.body("r_foot").xpos[0]))
        s.rows.append((d.time, sim.label, math.atan2(tu[0], tu[2]), float(d.subtree_com[pid][0]) - fx, float(d.subtree_linvel[pid][0]), ct["l_foot"] > 0.05, ct["r_foot"] > 0.05, float(d.xpos[pid][2])))
t = load_task("run_v4"); t.seed = seed
sim = Sim(t, params=read_params(params), controller=os.path.abspath(ctl))
r = R(); res = sim.run(secs, recorder=r)
print("fell", res.get("fell"), "time", res.get("time"), "peak", res.get("peak_speed_1s"))
for (tm, lab, p, cx, v, lc, rc, z) in r.rows:
    if t0 <= tm <= t1:
        print("%5.2f %-10s pitch %+.2f  com-feet %+.2f  v %+.2f  L%d R%d  pelvis_z %.2f" % (tm, lab, p, cx, v, lc, rc, z))
