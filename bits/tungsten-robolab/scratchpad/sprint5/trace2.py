"""trace2.py PARAMS CTL SEED SECS: joint angles (deg), COM-feet, torso pitch of the first seconds of one standing-start rollout (beyond body)."""
import os, sys, math
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
os.environ["ROBOLAB_CALIB"] = "v4"; os.environ["ROBOLAB_PROFILE"] = "beyond"; os.environ["ROBOLAB_PROFILE_PARTS"] = "strength,speed,tendon,activation"
sys.path.insert(0, os.path.join(ROOT, "playground"))
from practice import load_task, read_params
from bridge import Sim
params, ctl, seed, secs = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4])
class R:
    def __init__(s): s.nx = 0.0; s.rows = []
    def maybe_capture(s, sim):
        d = sim.d
        if d.time < s.nx: return
        s.nx = d.time + 0.1
        m = sim.m
        q = lambda n: math.degrees(float(d.qpos[m.joint(n).qposadr[0]]))
        pid = m.body("pelvis").id; tid = m.body("torso").id
        tu = d.xmat[tid].reshape(3, 3)[:, 2]
        fx = 0.5 * (float(d.body("l_foot").xpos[0]) + float(d.body("r_foot").xpos[0]))
        s.rows.append((d.time, sim.label, q("l_hip_flex"), q("l_knee"), q("l_ankle"), q("spine_flex"), q("root_pitch"), math.degrees(math.atan2(tu[0], tu[2])), float(d.subtree_com[pid][0]) - fx, float(d.xpos[pid][2])))
t = load_task("run_v4"); t.seed = seed
sim = Sim(t, params=read_params(params), controller=os.path.abspath(ctl))
r = R(); res = sim.run(secs, recorder=r)
print("seed", seed, "fell", res.get("fell"), "time", res.get("time"))
print(" t     chunk       hipL  kneeL  ankL  spine pelvP torsoP  com-feet pelvZ")
for row in r.rows: print("%4.1f %-11s %6.1f %6.1f %6.1f %6.1f %6.1f %6.1f  %+.3f %.3f" % row)
