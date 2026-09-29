"""Record running states (qpos, qvel, act) of a champion runner 8 ms before right touchdowns in steady running.
usage: snapshots.py TASK PARAMS CONTROLLER OUT.npz"""
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
from practice import load_task, read_params
from bridge import Sim
import numpy as np
task_name, par, ctl, out = sys.argv[1:5]
T0 = float(os.environ.get("T0", "8")); T1 = float(os.environ.get("T1", "99"))
class R:
    """A real right touchdown: the foot loads after >= 60 ms in the air, ahead of
    the COM (a foot rocking on its toe late in stance re-contacts briefly; those
    onsets are not touchdowns)."""
    def __init__(s): s.buf = []; s.snaps = []; s.prev = True; s.off_since = 0.0
    def maybe_capture(s, sim):
        d = sim.d
        on = sim.contacts()["r_foot"] > 0.05
        pid = sim.m.body("pelvis").id
        s.buf.append((d.time, d.qpos.copy(), d.qvel.copy(), d.act.copy(), float(d.subtree_linvel[pid][0])))
        s.buf = s.buf[-4:]
        ahead = float(d.body("r_foot").xpos[0]) > float(d.subtree_com[pid][0])
        if on and not s.prev and d.time - s.off_since >= 0.06 and ahead and T0 <= d.time <= T1 and len(s.buf) >= 3:
            s.snaps.append(s.buf[-3])  # two control ticks before the touchdown tick
        if s.prev and not on:
            s.off_since = d.time
        s.prev = on
t = load_task(task_name); t.seed = (int(os.environ["SEED"]) if os.environ.get("SEED") else None)
sim = Sim(t, params=read_params(par), controller=None if ctl == "-" else ctl)
r = R(); res = sim.run(float(os.environ.get("SECS", "20")), recorder=r)
print(res["time"], res["fell"], res.get("steady_speed"), len(r.snaps), "snapshots; speeds", [round(x[4], 2) for x in r.snaps])
np.savez_compressed(out, t=np.array([x[0] for x in r.snaps]), qpos=np.array([x[1] for x in r.snaps]), qvel=np.array([x[2] for x in r.snaps]),
                    act=np.array([x[3] for x in r.snaps]), vx=np.array([x[4] for x in r.snaps]), root_x_adr=t.__class__.__name__)
