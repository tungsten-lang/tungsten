import os, sys, numpy as np, mujoco
sys.path.insert(0, "playground"); sys.path.insert(0, "playground/tasks")
from dribble_v3 import DribbleV3Task
t = DribbleV3Task()
b = t.builder()
m = mujoco.MjModel.from_xml_string(t.xml(b)); d = mujoco.MjData(m)
t.reset(m, d)
names = ["hip_flex", "hip_abd", "hip_rot", "knee", "ankle"]
def setleg(side, q):
    for n, v in zip(names, q): d.joint(f"{side}_{n}").qpos[0] = v
front = [0.778, 0.109, 0.084, 0.679, 0.087]; back = [0.223, 0.235, 0.064, 0.904, -0.59]
ath = [0.57, 0.1, 0.0, 1.14, -0.57]
for label, (lq, rq) in {"athletic": (ath, ath), "l_lead": (front, back)}.items():
    setleg("l", lq); setleg("r", rq); mujoco.mj_forward(m, d)
    print(label, "pelvis", d.body("pelvis").xpos.round(3))
    for s in "lr":
        print(" ", s, "hip", d.body(f"{s}_thigh").xpos.round(3), "knee", d.body(f"{s}_shin").xpos.round(3), "ankle", d.body(f"{s}_foot").xpos.round(3),
              "foot geom", d.geom(f"{s}_foot").xpos.round(3), "floor z of foot bottom", round(d.geom(f"{s}_foot").xpos[2]-0.025,3))
