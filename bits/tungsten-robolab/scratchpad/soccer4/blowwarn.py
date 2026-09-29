"""Dump the simulator state at the moment MuJoCo raises its instability warning (user-warning callback).
usage: blowwarn.py <params> <controller> <seed> <seconds> [k=v,...]
The callback runs inside mj_step before the data is reset, so the contacts, qacc and efc are the bad step's."""
import os, sys, math
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
os.environ["MYO_SOCCER_MAX_TIME"] = "310"
import mujoco
from search4 import read_params
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask

params = read_params(sys.argv[1]); ctl = os.path.abspath(sys.argv[2]); seed = int(sys.argv[3]); secs = float(sys.argv[4])
if len(sys.argv) > 5:
    for kv in sys.argv[5].split(","):
        if "=" in kv:
            k, v = kv.split("="); params[k] = float(v)
holder = {}
hist = []


def dump(msg):
    print("MUJOCO WARNING:", msg, flush=True)
    sim = holder.get("sim")
    if sim is None:
        return
    m, d = sim.m, sim.d
    print(f"  time {d.time:.4f} ncon {d.ncon} nefc {d.nefc} niter {d.solver_niter[0] if hasattr(d, 'solver_niter') else '?'}")
    qa = np.abs(d.qacc)
    order = np.argsort(-np.nan_to_num(qa, nan=1e30, posinf=1e30))[:5]
    for i in order:
        j = m.dof_jntid[i]
        print(f"  dof {i} {mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_JOINT, j)} qacc {d.qacc[i]:.4g} qvel {d.qvel[i]:.4g}")
    f6 = np.zeros(6)
    rows = []
    for i in range(d.ncon):
        c = d.contact[i]
        g1, g2 = c.geom1, c.geom2
        mujoco.mj_contactForce(m, d, i, f6)
        rows.append((float(np.abs(f6[:3]).max()) if np.all(np.isfinite(f6)) else 1e30, mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_GEOM, g1) or f"geom{g1}", m.body(m.geom_bodyid[g1]).name,
                     mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_GEOM, g2) or f"geom{g2}", m.body(m.geom_bodyid[g2]).name, c.dist, c.frame[:3].copy(), c.efc_address))
    rows.sort(key=lambda r: -r[0])
    print("  largest contacts (force N, geom1 [body], geom2 [body], dist mm, normal):")
    for f, n1, b1, n2, b2, dist, nrm, adr in rows[:6]:
        print(f"    {f:12.4g} {n1} [{b1}] - {n2} [{b2}] dist {dist * 1000:+.3f} normal {np.round(nrm, 3)}")
    print("  previous control steps (t, largest non-world contact force, its bodies):")
    for h in hist[-8:]:
        print("   ", h)
    holder["done"] = True


mujoco.set_mju_user_warning(dump)


class T(MyoSoccerTask):
    def on_step(self, sim, obs, reward, info):
        super().on_step(sim, obs, reward, info)
        holder["sim"] = sim
        m, d = sim.m, sim.d
        f6 = np.zeros(6)
        best = (0.0, "", "")
        for i in range(d.ncon):
            c = d.contact[i]
            b1, b2 = m.body(m.geom_bodyid[c.geom1]).name, m.body(m.geom_bodyid[c.geom2]).name
            if b1 == "world" or b2 == "world":
                continue
            mujoco.mj_contactForce(m, d, i, f6)
            if abs(f6[0]) > best[0]:
                best = (float(abs(f6[0])), b1, b2)
        hist.append(f"t {d.time:.3f} {best[1]}-{best[2]} {best[0]:.1f} N ncon {d.ncon} |qacc|max {float(np.abs(d.qacc).max()):.3g}")
        if holder.get("done"):
            raise SystemExit(0)


sim = MyoSim(T(), params=params, controller=ctl, seed=seed)
holder["sim"] = sim
try:
    r = sim.run(secs)
    print("result", {k: r.get(k) for k in ("bal1_s", "stand_time", "fallen")})
except SystemExit:
    pass
