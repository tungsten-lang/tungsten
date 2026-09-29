"""Kinematic clearance of the swing leg from the stance leg in the hold: sweep the swing hip/knee angles at the hold state."""
import os, sys, itertools
import numpy as np, mujoco
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
os.environ["MYO_SOCCER_MAX_TIME"] = "310"
from search4 import read_params
from myo_bridge import MyoSim
from tasks.myo_soccer import MyoSoccerTask
p = read_params("params/myo_soccer_single_leg_310_ramp.txt")
state = {}
class T(MyoSoccerTask):
    def on_step(self, sim, obs, reward, info):
        super().on_step(sim, obs, reward, info)
        if float(sim.d.time) >= 4.0 and "q" not in state:
            state["q"] = sim.d.qpos.copy()
sim = MyoSim(T(), params=p, controller="bin/challengers/soccer6-i", seed=90000)
sim.run(4.05)
m = sim.m
d = mujoco.MjData(m)
d.qpos[:] = state["q"]
mujoco.mj_forward(m, d)
def adr(n): return m.jnt_qposadr[m.joint(n).id]
cur = {n: float(d.qpos[adr(n)]) for n in ("hip_flexion_r", "hip_adduction_r", "hip_rotation_r", "knee_angle_r", "ankle_angle_r")}
print("hold pose (swing leg):", {k: round(v, 3) for k, v in cur.items()})
def geoms(bodies):
    out = []
    for g in range(m.ngeom):
        if m.body(m.geom_bodyid[g]).name in bodies and m.geom_contype[g] + m.geom_conaffinity[g] > 0:
            out.append(g)
    return out
sw = geoms({"tibia_r", "talus_r", "calcn_r", "toes_r"})
st = geoms({"femur_l", "tibia_l"})
def clearance(dd):
    best = 1.0
    fromto = np.zeros(6)
    for a in sw:
        for b in st:
            if m.geom_bodyid[a] == m.geom_bodyid[b]: continue
            dist = mujoco.mj_geomDistance(m, dd, a, b, 0.3, fromto)
            best = min(best, dist)
    return best
print("clearance at the hold pose: %.4f m" % clearance(d))
# sweep
res = []
for add, rot, kn, hf in itertools.product([cur["hip_adduction_r"] + x for x in (-0.3, -0.2, -0.1, 0.0)],
                                          [cur["hip_rotation_r"] + x for x in (-0.6, -0.3, 0.0, 0.3, 0.6)],
                                          [cur["knee_angle_r"] + x for x in (-0.6, -0.3, 0.0)],
                                          [cur["hip_flexion_r"] + x for x in (-0.3, 0.0, 0.3, 0.6)]):
    dd = mujoco.MjData(m); dd.qpos[:] = state["q"]
    for n, v in (("hip_adduction_r", add), ("hip_rotation_r", rot), ("knee_angle_r", kn), ("hip_flexion_r", hf)):
        lo, hi = m.jnt_range[m.joint(n).id]
        dd.qpos[adr(n)] = min(max(v, lo), hi)
    mujoco.mj_forward(m, dd)
    res.append((clearance(dd), add - cur["hip_adduction_r"], rot - cur["hip_rotation_r"], kn - cur["knee_angle_r"], hf - cur["hip_flexion_r"]))
res.sort(key=lambda r: -r[0])
print("best clearances (d_add, d_rot, d_knee, d_hf):")
for r in res[:12]:
    print("  clearance %.3f  add %+.2f rot %+.2f knee %+.2f hf %+.2f" % r)
ok = [r for r in res if r[0] > 0.01]
ok.sort(key=lambda r: abs(r[1]) + abs(r[2]) + abs(r[3]) + abs(r[4]))
print("closest to the hold pose with clearance > 1 cm:")
for r in ok[:8]:
    print("  clearance %.3f  add %+.2f rot %+.2f knee %+.2f hf %+.2f" % r)
