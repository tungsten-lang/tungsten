"""Replay a saved oracle program (oracle_search.py npz) and print the arm's joints and the ball through the stroke."""
import sys
sys.path.insert(0, "scratchpad/btl2")
import numpy as np, mujoco
import oracle_lib as O
from common import load
import oracle_search as S
z = np.load(sys.argv[1])
seed, t_snap = int(z["seed"]), float(z["t_snap"])
params = load("params/dribble_btl_a4.txt")
rec = O.record(seed, params, "bin/challengers/btl2-b1", t_snap, t_snap + 0.85)
rp = O.Replay(rec)
k0 = rec["k0"]; n = 160
idx, kt, x = list(z["idx"]), z["kt"], z["x"]
nprog = int(kt[-1])
base = rec["acts"][k0:k0 + n + 1]
X = np.clip(x.reshape(len(idx), len(kt)), 0, 1)
ov = {}
for r, mi in enumerate(idx):
    arr = base[:n, mi].copy(); arr[:nprog + 1] = np.interp(np.arange(nprog + 1), kt, X[r]); ov[mi] = arr
m, d = rp.m, rp.d
names = ["shoulder_flex", "shoulder_abd", "shoulder_rot", "elbow", "wrist_flex", "wrist_dev"]
rp.load()
ids = rp.act_ids
print("t     ball xyz v | palm xyz v | l joints (sf sa sr el wf wd) | contact l")
vel = np.zeros(6)
for i in range(n):
    a = base[i].copy()
    for mi, arr in ov.items(): a[mi] = arr[i]
    d.ctrl[ids] = a
    for _ in range(5): mujoco.mj_step(m, d)
    if i % 2 == 0 and i < 120:
        p = d.xpos[rp.ball_id]; v = d.qvel[rp.ball_dof:rp.ball_dof + 3]
        sid = m.site("l_palm").id; mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_SITE, sid, vel, 0)
        q = [float(d.qpos[m.jnt_qposadr[m.joint("l_" + nme).id]]) for nme in names]
        f = rp.contacts()
        print(f"{d.time:.3f} ball {p[0]:+.2f} {p[1]:+.2f} {p[2]:.2f} v {v[0]:+.2f} {v[1]:+.2f} {v[2]:+.2f} | palm {d.site('l_palm').xpos[0]:+.2f} {d.site('l_palm').xpos[1]:+.2f} {d.site('l_palm').xpos[2]:.2f} v {vel[3]:+.2f} {vel[4]:+.2f} {vel[5]:+.2f} | q " + " ".join(f"{x:+.2f}" for x in q) + f" | T {f['l']:.1f}")
