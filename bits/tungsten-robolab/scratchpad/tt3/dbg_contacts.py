"""Debug (agent T3): which geoms the ball touches in an O4 episode."""
import os, sys
os.environ.setdefault("TT_ENV", "P2"); os.environ["TT_TASK"] = "myo_tt_oracle"; os.environ["MYO_TT_ORACLE"] = "o4"
os.environ["TT3_PLAN"] = sys.argv[2] if len(sys.argv) > 2 else "scratchpad/tt3/results/plan_a.json"
HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(HERE, "playground"))
import numpy as np, mujoco
import tt_fast
from tasks import myo_tt_oracle as mto
params = tt_fast.read_params("params/myo_tt_p2_r10_c3.txt")
ctl = os.path.abspath("bin/challengers/myo_tt_r10-n")
seed = int(sys.argv[1])
task = mto.TASK(); task.env_id = "myoChallengeTableTennisP2-v0"
sim = tt_fast.make_sim(task, params, seed, controller=ctl)
seen = []
orig_step = mujoco.mj_step
import types
def hook_adv(o):
    old = o.advance
    def adv(model, data, n_frames=1, render=None):
        for _ in range(n_frames):
            if o.q_ref is not None and o.fit is not None and "o2" in o.modes:
                pass
            if o.plan is not None:
                o.puppet(model, data)
            mujoco.mj_step(model, data)
            for i in range(data.ncon):
                c = data.contact[i]
                g1, g2 = int(c.geom1), int(c.geom2)
                bid = model.geom("pingpong").id
                if bid in (g1, g2):
                    other = g2 if g1 == bid else g1
                    nm = model.geom(other).name or f"geom{other}({model.body(model.geom_bodyid[other]).name})"
                    seen.append((round(float(data.time), 3), nm, np.round(data.qvel[64:67], 2).tolist(), np.round(data.qpos[65:68], 3).tolist()))
    return adv
o0 = None
orig_extra = task.extra_sensors
def extra(sim_):
    r = orig_extra(sim_)
    global o0
    if o0 is None and hasattr(sim_, "_orc"):
        o0 = sim_._orc
        sim_.u.robot._advance = hook_adv(o0)
    return r
task.extra_sensors = extra
res = sim.run()
print("solved", res.get("solved"), "hit", res.get("hit"), "landed", res.get("landed"), "t_contact", res.get("t_contact"))
last = None
for s in seen:
    key = (s[1])
    print(s)
pl = mto.Oracle._plans[str(seed)]
print("plan t_hit", pl["t_hit"], "P", np.round(pl["P"], 3), "n_out", np.round(pl["n_out"], 3), "v", pl["v"])
