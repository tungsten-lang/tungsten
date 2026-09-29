"""Print time series of a dumped run (checkpoint pickle): toe y, pelvis yaw, right hip angles, left foot slip..."""
import gzip, pickle, sys, glob
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import kcommon as K
K.ensure()
import mujoco
from myosuite.utils import gym as mgym
_env = mgym.make("myoChallengeSoccerP2-v0"); _env.reset(seed=0)
M = _env.unwrapped.mj_model
J = {n: M.jnt_qposadr[M.joint(n).id] for n in ["hip_flexion_r","hip_adduction_r","hip_rotation_r","knee_angle_r","ankle_angle_r","hip_flexion_l","hip_adduction_l","hip_rotation_l","knee_angle_l","ankle_angle_l","flex_extension","lat_bending","axial_rotation"]}

def load(path):
    with gzip.open(path, "rb") as f:
        return pickle.load(f)

def series(path, t0=1.70, t1=2.10, step=2):
    p = load(path)
    tr, st = p["trace"], p["state"]
    print(path.split("/")[-1], "ok", p["row"]["kick_ok"], "ball", p["row"]["ball_speed"], "touch", p["row"]["t_touch"])
    print("   t   lab   toe(y-ball) toe_z  pelv_y  yaw  | hipF  hipAdd  hipRot  knee  ankle | Lhip add rot | vtoe_x vtoe_y | ank_r y")
    for j in range(len(tr)):
        r = tr[j]
        if r["t"] < t0 or r["t"] > t1 or (j % step):
            continue
        q = st[j]["qpos"]
        b = r["bof_r"] - r["ball"]
        print(f" {r['t']:.2f} {r['lab']:6s} {b[1]:+.3f} {b[2]:+.3f} {r['pelvis'][1]:+.3f} {r['yaw']:+.2f} | {q[J['hip_flexion_r']]:+.2f} {q[J['hip_adduction_r']]:+.2f} {q[J['hip_rotation_r']]:+.2f} {q[J['knee_angle_r']]:+.2f} {q[J['ankle_angle_r']]:+.2f} | {q[J['hip_adduction_l']]:+.2f} {q[J['hip_rotation_l']]:+.2f} | {r['vtoe_r'][0]:+.1f} {r['vtoe_r'][1]:+.1f} | {r['ank_r'][1]-r['ball'][1]:+.3f}")

if __name__ == "__main__":
    for path in sys.argv[1:]:
        series(path)
